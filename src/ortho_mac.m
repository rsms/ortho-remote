// clang -std=c11 -Wall -framework CoreFoundation -framework CoreBluetooth ble1.m -o ble1
#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include "ortho.h"

#define UNUSED __attribute__((unused))

static NSString* kPeripheralName = @"ortho remote";

// MIDI 1 message protocol constants
// Status Description        Msg size  Byte 1      Byte 2
// 8x     note off           2         pitch       velocity
// 9x     note on            2         pitch       velocity
// Bx     controller change  2         controller  value
// ...
// Source: https://www.cs.cmu.edu/~music/cmsip/readings/davids-midi-spec.htm
#define MIDI1_H_NOTE_OFF 0x8
#define MIDI1_H_NOTE_ON  0x9
#define MIDI1_H_CTRL_CH  0xB

#define MIDI1_SYSEX_START 0xf0
#define MIDI1_SYSEX_END   0xf7

static CBUUID* kCBUUID_Service_DevInfo = nil;  // Device Information
static CBUUID* kCBUUID_Service_Battery = nil;  // Battery
static CBUUID* kCBUUID_Service_BLE_MIDI = nil; // BLE MIDI
static CBUUID* kCBUUID_Service_TE_Ortho = nil; // Ortho Remote-specific service UUID (unknown)

static CBUUID* kCBUUID_Chari_BatteryLevel = nil; // Battery level
static CBUUID* kCBUUID_Chari_MIDI = nil;         // MIDI characteristic
static CBUUID* kCBUUID_Chari_TE_Ortho1 = nil;    // Ortho Remote-specific (unknown)

static void __attribute__((constructor)) init() {
  kCBUUID_Service_DevInfo  = [CBUUID UUIDWithString:@"180A"];
  kCBUUID_Service_Battery  = [CBUUID UUIDWithString:@"180F"];
  kCBUUID_Service_BLE_MIDI = [CBUUID UUIDWithString:@"03B80E5A-EDE8-4B33-A751-6CE34EC4C700"];
  kCBUUID_Service_TE_Ortho = [CBUUID UUIDWithString:@"20454C45-4354-5241-2052-554C45532120"];

  kCBUUID_Chari_BatteryLevel = [CBUUID UUIDWithString:@"2A19"];
  kCBUUID_Chari_MIDI         = [CBUUID UUIDWithString:@"7772E5DB-3868-4112-A1A9-F2669D106BF3"];
  kCBUUID_Chari_TE_Ortho1    = [CBUUID UUIDWithString:@"20454C46-4354-5241-2052-554C45532120"];
}

#ifdef NDEBUG
  #define dlog(fmt, ...) ((void)0)
#else
  #define dlog(fmt, ...) ({ \
    const char* cstr = [@"# " stringByAppendingFormat:fmt "\n", ##__VA_ARGS__].UTF8String; \
    fwrite(cstr, strlen(cstr), 1, stderr); \
  })
#endif


@interface BTObj : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@end

typedef struct Ortho {
  BTObj*           btobj;
  ortho_msg_fn     msgcb;
  void*            userdata;
  ortho_memfree_fn memfree;
} Ortho;


static void on_midi_msg(Ortho* o, const uint8_t* data, size_t len) {
  if (len < 3)
    return;

  // MIDI BLE Packet:
  //
  // field  | bit: 0  1  2  3  4  5  6  7
  // -------+----- -- -- -- -- -- -- -- --
  // header        1  r  <-timestamp_hi ->
  // timestamp_lo  1  <-  timestamp_lo  ->
  // status        1  <-      code      ->
  // data1         0  ...
  // dataN         0  ...

  if (((0xF0 & data[0]) >> 7) == 0) {
    // unexpected data byte (remaining 7 bits are data bits)
    return;
  }

  // MSB is 1 -- this is a status message
  if (data[0] == MIDI1_SYSEX_END) {
    // ignore
    return;
  }

  // uint8_t r = data[0] & 0x40;
  // uint32_t timestamp = ((data[1] & 0x7f)) | ((data[0] & 0x3f) << 8);
  // fprintf(stderr, "[r %u, ts %u] ", r, timestamp);

  OrthoMsg msg = {0};

  switch ((data[2] >> 4) & 0xF) {
    case MIDI1_H_NOTE_OFF:
      // payload: 2 bytes
      dlog(@"button released (pitch %02X, velocity %02X)", data[3], data[4]);
      msg.ev = ORTHO_RESTING;
      break;

    case MIDI1_H_NOTE_ON:
      // payload: 2 bytes (pitch, velocity)
      dlog(@"button depressed (pitch %02X, velocity %02X)", data[3], data[4]);
      msg.ev = ORTHO_PRESSED;
      break;

    case MIDI1_H_CTRL_CH: {
      // payload: 2 bytes (controller id, value 00–7f)
      msg.value = (float)data[4] / (float)0x7f;
      dlog(@"rotated (controller %02X, value %f)", data[3], msg.value);
      msg.ev = ORTHO_VALUE;
      break;
    }

    default:
      dlog(@"unexpected MIDI message 0x%02X", (data[2] & 0x7f));
      return;
  }

  o->msgcb(&msg, o->userdata);
}


typedef enum ScanState {
  ScanOff,
  ScanOn,
} ScanState;


@implementation BTObj {
  CBCentralManager* _centralManager;
  CBPeripheral*     _peripheral;
  ScanState         _scanState;
  Ortho*            _ortho;
}

- (instancetype)initWithOrtho:(Ortho*)ortho {
  self = [super init];
  _scanState = ScanOff;
  _ortho = ortho;
  // NOTE: Creating the CBCentralManager with initWithDelegate will immediately call centralManagerDidUpdateState.
  _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
  return self;
}


- (void)stopScan {
  // Scanning uses up battery on phone, so pause the scan process for the designated interval.
  if (_scanState != ScanOff) {
    _scanState = ScanOff;
    dlog(@"scan stop");
    // [NSTimer scheduledTimerWithTimeInterval:10.0
    //   target:self selector:@selector(startScan) userInfo:nil repeats:NO];
    [_centralManager stopScan];
  }
}

- (void)setPeripheral:(CBPeripheral*)peripheral {
  if (_peripheral) {
    _peripheral.delegate = nil;
  }
  _peripheral = peripheral;
  _peripheral.delegate = self;
}

- (void)startScan {
  if (_scanState != ScanOn) {
    // see if the peripheral is already connected
    CBPeripheral* peripheral = [self findAlredyConnectedPeripheral];
    if (peripheral) {
      [self setPeripheral:peripheral];
      dlog(@"use already-connected device %@", _peripheral);
      // Note: we must "connectPeripheral" even when a peripheral is already "connected".
      // Simply calling [p discoverServices] does not work.
      [_centralManager connectPeripheral:_peripheral options:nil];
    } else {
      _scanState = ScanOn;
      dlog(@"scanning for \"%@\" ...", kPeripheralName);
      // [NSTimer scheduledTimerWithTimeInterval:10.0
      //   target:self selector:@selector(stopScan) userInfo:nil repeats:NO];
      [_centralManager scanForPeripheralsWithServices:nil options:nil];
    }
  }
}

- (CBPeripheral*)findAlredyConnectedPeripheral {
  // Note: IOBluetooth has the ability to list all connected devices without requiring
  // a list of service IDs. However the UUIDs used by Core Bluetooth are opaque and
  // can not be converted or bridged, so even if we did use IOBluetooth we would not be
  // able to derive the device UUID needed for Core Bluetooth.
  // #import <IOBluetooth/IOBluetooth.h>
  // NSArray<IOBluetoothDevice*>* pairedDevices = [IOBluetoothDevice pairedDevices];
  // if (!pairedDevices)
  //   return nil;
  // // dlog(@"pairedDevices %@", pairedDevices);
  // for (IOBluetoothDevice* dev in pairedDevices) {
  //   dlog(@"paired device: \"%@\" (addr %@)", dev.nameOrAddress, dev.addressString);
  // }

  // BLE service IDs to scan for. The values are logically OR (not AND) -ed together.
  NSArray<CBUUID*>* serviceUUIDs = @[
    // "BLE MIDI" service UUID that mysteriously is printed as "BLE MIDI" in NSLog
    //kCBUUID_Service_BLE_MIDI,
    // Ortho Remote-specific service UUID (unknown protocol)
    kCBUUID_Service_TE_Ortho,
  ];
  NSArray<CBPeripheral*>* peripherals =
    [_centralManager retrieveConnectedPeripheralsWithServices:serviceUUIDs];
  dlog(@"connected peripherals: %@", peripherals);
  for (CBPeripheral* p in peripherals) {
    //dlog(@"currently-connected peripheral \"%@\" (UUID %@)", p.name, p.identifier.UUIDString);
    if ([p.name isEqualToString:kPeripheralName]) {
      return p;
    }
  }
  return nil;
}

- (void)onPeripheralConnected {
  CBPeripheral* p = _peripheral;
  dlog(@"connected to \"%@\" (UUID %@) ", p.name, p.identifier.UUIDString);
  [p discoverServices:nil];
}


// ———————————————————————————————————————————————————————————————————————————————————————————
// CBCentralManagerDelegate methods

// step 1
- (void)centralManagerDidUpdateState:(CBCentralManager*)central {
  switch (central.state) {
    case CBManagerStateUnsupported:
      dlog(@"cbmanager state=Unsupported");
      break;
    case CBManagerStateUnauthorized:
      dlog(@"cbmanager state=Unauthorized");
      break;
    case CBManagerStatePoweredOff:
      dlog(@"cbmanager state=PoweredOff");
      break;
    case CBManagerStateResetting:
      dlog(@"cbmanager state=Resetting");
      break;
    case CBManagerStatePoweredOn:
      dlog(@"cbmanager state=PoweredOn (ready for communication)");
      [self startScan];
      break;
    case CBManagerStateUnknown:
      dlog(@"cbmanager state=Unknown (The state of the BLE Manager is unknown)");
      break;
    default:
      dlog(@"The state of the BLE Manager is unknown");
  }
}

// step 2
- (void) centralManager:(CBCentralManager*)central
  didDiscoverPeripheral:(CBPeripheral*)peripheral
      advertisementData:(NSDictionary*)advertisementData
                   RSSI:(NSNumber*)RSSI
{
  if (_scanState == ScanOff)
    return;
  // NSString* pname = [advertisementData objectForKey:@"kCBAdvDataLocalName"];
  NSString* pname = peripheral.name;
  UNUSED NSUUID* peerUUID = peripheral.identifier;

  // DEBUG LOG
  if (!pname || pname.length == 0) // skip unnamed peripherals
    return;
  dlog(@"scan found device \"%@\" (UUID %@, RSSI %@)",
   pname ? pname : @"", peerUUID.UUIDString, RSSI);

  if (!pname || ![pname isEqualToString:kPeripheralName])
    return;

  dlog(@"connecting to \"%@\" (UUID %@) ...", pname, peerUUID.UUIDString);
  [self stopScan];

  // save a reference to the peripheral
  [self setPeripheral:peripheral];
  _peripheral = peripheral;
  _peripheral.delegate = self;

  // Request a connection to the peripheral
  [_centralManager connectPeripheral:_peripheral options:nil];
}


// step 3 (A)
- (void)centralManager:(CBCentralManager*)central
        didConnectPeripheral:(CBPeripheral*)peripheral
{
  assert(_peripheral == peripheral);
  [self onPeripheralConnected];
}

// step 3 (B)
- (void)centralManager:(CBCentralManager*)central
        didFailToConnectPeripheral:(CBPeripheral*)peripheral
        error:(NSError*)error
{
  dlog(@"connection failed with error %@", error.localizedDescription);
  exit(1); // FIXME
}


- (void)centralManager:(CBCentralManager*)central
        didDisconnectPeripheral:(CBPeripheral*)peripheral
        error:(NSError*)error
{
  dlog(@"device disconnected (error=%@)", error);
  OrthoMsg msg = { .ev = ORTHO_DISCONNECT };
  _ortho->msgcb(&msg, _ortho->userdata);
  [self startScan]; // TODO: consider using a delay
}


// ———————————————————————————————————————————————————————————————————————————————————————————
// CBPeripheralDelegate methods

// When the specified services are discovered, the peripheral calls the
// peripheral:didDiscoverServices: method of its delegate object
- (void)peripheral:(CBPeripheral*)peripheral didDiscoverServices:(NSError*)error {
  // Core Bluetooth creates an array of CBService objects:
  // one for each service that is discovered on the peripheral.
  for (CBService* service in peripheral.services) {
    dlog(@"discovered service: %@ (%@)", service, service.UUID.UUIDString);
    if (([service.UUID isEqual:kCBUUID_Service_BLE_MIDI]) ||
        ([service.UUID isEqual:kCBUUID_Service_TE_Ortho]) ||
        ([service.UUID isEqual:kCBUUID_Service_Battery]) )
    {
      [peripheral discoverCharacteristics:nil forService:service];
    }
  }
}

- (void)peripheral:(CBPeripheral*)peripheral
        didDiscoverCharacteristicsForService:(CBService*)service
        error:(NSError*)error
{
  //dlog(@"didDiscoverCharacteristicsForService %@", service);
  if (error) {
    dlog(@"error while discovering device characteristics: %@", error.localizedDescription);
    return;
  }
  for (CBCharacteristic* c in service.characteristics) {
    if ([c.UUID isEqual:kCBUUID_Chari_BatteryLevel]) {
      [peripheral setNotifyValue:YES forCharacteristic:c];
    } else if ([c.UUID isEqual:kCBUUID_Chari_MIDI]) {
      [peripheral setNotifyValue:YES forCharacteristic:c];
    } else if ([c.UUID isEqual:kCBUUID_Chari_TE_Ortho1]) {
      [peripheral setNotifyValue:YES forCharacteristic:c];
      OrthoMsg msg = { .ev = ORTHO_CONNECT };
      _ortho->msgcb(&msg, _ortho->userdata);
    }
    //dlog(@"  %@ (%@)", c, c.UUID.UUIDString);
  }
}

- (void)peripheral:(CBPeripheral*)peripheral
        didUpdateValueForCharacteristic:(CBCharacteristic*)c
        error:(NSError*)error
{
  //dlog(@"didUpdateValueForCharacteristic %@", c);
  if (error) {
    dlog(@"error while updating value for chari %@: %@", c, error.localizedDescription);
    return;
  }
  NSData* data = c.value;
  if ([c.UUID isEqual:kCBUUID_Chari_MIDI]) {
    on_midi_msg(_ortho, (const uint8_t*)data.bytes, (size_t)data.length);
  } else if ([c.UUID isEqual:kCBUUID_Chari_BatteryLevel]) {
    dlog(@"battery level: %@", data);
  } else {
    dlog(@"unexpected value received: %@ => %@", c, data);
  }
}


@end


Ortho* ortho_create(ortho_memalloc_fn memalloc, ortho_memfree_fn memfree) {
  Ortho* o = memalloc(sizeof(Ortho));
  memset((void*)o, 0, sizeof(Ortho));
  o->memfree = memfree;
  return o;
}

void ortho_free(Ortho* o) {
  if (o->btobj) {
    [o->btobj stopScan];
    o->btobj = nil;
  }
  o->memfree(o);
}

int ortho_runloop(Ortho* o, ortho_msg_fn msgcb, void* userdata) {
  o->msgcb = msgcb;
  o->userdata = userdata;
  @autoreleasepool {
    o->btobj = [[BTObj alloc] initWithOrtho:o];
    [[NSRunLoop mainRunLoop] run];
  }
  return 0;
}
