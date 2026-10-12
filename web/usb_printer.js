// WebUSB for UzaPay's receipt printers: choose a USB printer, then send it the
// same ESC/POS bytes the Android app sends a network printer.
//
// Exposed as `UzaPayUsbPrinter` and called from
// `lib/checkout/checkout_print_transport_web.dart` through `dart:js_interop`.
// Every call resolves to a JSON string `{ ok, code, ... }` and never rejects,
// so a failure arrives in Dart as a code rather than as a JavaScript exception.
//
// Codes: `unsupported` (no WebUSB here), `not_found` (the printer is not among
// the devices this site may use - unplugged, off, or permission withdrawn),
// `busy` (another program holds it; on Windows, the printer's own driver),
// `write_timeout` (it stopped taking bytes part-way), `failed` (anything else).
(function () {
  'use strict';

  // The USB class a printer declares itself as. Receipt printers that report
  // a maker's own class instead are reached through `choose(true)`.
  const PRINTER_CLASS = 7;

  // Small enough for every receipt printer's buffer, large enough that a
  // receipt with a logo is a handful of transfers.
  const CHUNK_BYTES = 4096;

  const OPEN_TIMEOUT_MS = 5000;
  const WRITE_TIMEOUT_MS = 8000;

  function isSupported() {
    return typeof navigator !== 'undefined' &&
      !!navigator.usb &&
      typeof navigator.usb.requestDevice === 'function' &&
      globalThis.isSecureContext === true;
  }

  function answer(fields) {
    return JSON.stringify(fields);
  }

  function failure(code, error) {
    const name = error && error.name ? error.name : '';
    const message = error && error.message ? error.message : '';
    return answer({ ok: false, code: code, detail: (name + ': ' + message).trim() });
  }

  function describe(device) {
    return {
      vendorId: device.vendorId,
      productId: device.productId,
      serialNumber: device.serialNumber || null,
      productName: device.productName || null,
      manufacturerName: device.manufacturerName || null,
    };
  }

  function named(name, message) {
    const error = new Error(message);
    error.name = name;
    return error;
  }

  // Which code a WebUSB failure is. Windows refuses a device its printer
  // driver holds as `SecurityError: Access denied`, and a claimed interface
  // as `NetworkError: Unable to claim interface` - both mean the same thing
  // to the person at the till, and the app tells them how to free it.
  function classify(error) {
    const name = error && error.name ? error.name : '';
    const message = String(error && error.message ? error.message : '').toLowerCase();
    if (name === 'TimeoutError') return 'write_timeout';
    if (name === 'NotFoundError') return 'not_found';
    if (name === 'SecurityError' || name === 'InvalidStateError') return 'busy';
    if (message.includes('claim') || message.includes('access denied') ||
        message.includes('in use') || message.includes('busy')) {
      return 'busy';
    }
    if (message.includes('disconnected') || message.includes('no device')) {
      return 'not_found';
    }
    return 'failed';
  }

  async function withTimeout(promise, timeoutMs, label) {
    let timer;
    try {
      return await Promise.race([
        promise,
        new Promise(function (_, reject) {
          timer = setTimeout(function () {
            reject(named('TimeoutError', label + ' timed out'));
          }, timeoutMs);
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }

  function parseKey(key) {
    const parts = String(key).split(':');
    if (parts.length < 2) return null;
    const vendorId = parseInt(parts[0], 16);
    const productId = parseInt(parts[1], 16);
    if (!Number.isFinite(vendorId) || !Number.isFinite(productId)) return null;
    return {
      vendorId: vendorId,
      productId: productId,
      serialNumber: parts.length > 2 ? parts.slice(2).join(':') : null,
    };
  }

  async function find(key) {
    const wanted = parseKey(key);
    if (!wanted) return null;
    const devices = await navigator.usb.getDevices();
    return devices.find(function (device) {
      return device.vendorId === wanted.vendorId &&
        device.productId === wanted.productId &&
        (!wanted.serialNumber || device.serialNumber === wanted.serialNumber);
    }) || null;
  }

  // The interface and endpoint the bytes go out on: an interface of the
  // printer class where there is one, otherwise the first with a bulk OUT
  // endpoint - which is how a vendor-class receipt printer is reached.
  function bulkOut(configuration) {
    let fallback = null;
    for (const iface of configuration.interfaces) {
      for (const alternate of iface.alternates) {
        const endpoint = alternate.endpoints.find(function (candidate) {
          return candidate.direction === 'out' && candidate.type === 'bulk';
        });
        if (!endpoint) continue;
        const target = {
          interfaceNumber: iface.interfaceNumber,
          alternateSetting: alternate.alternateSetting,
          endpointNumber: endpoint.endpointNumber,
        };
        if (alternate.interfaceClass === PRINTER_CLASS) return target;
        if (!fallback) fallback = target;
      }
    }
    return fallback;
  }

  // Opens the printer, claims its interface, runs `work`, and always lets go:
  // a printer left claimed by this tab is a printer the next receipt - from
  // this tab or another - cannot reach.
  async function withPrinter(key, work) {
    if (!isSupported()) return answer({ ok: false, code: 'unsupported' });
    let device;
    try {
      device = await find(key);
    } catch (error) {
      return failure(classify(error), error);
    }
    if (!device) return answer({ ok: false, code: 'not_found' });
    let claimed = null;
    try {
      if (!device.opened) {
        await withTimeout(device.open(), OPEN_TIMEOUT_MS, 'Opening the printer');
      }
      if (device.configuration === null) await device.selectConfiguration(1);
      const target = bulkOut(device.configuration);
      if (!target) return answer({ ok: false, code: 'failed', detail: 'No bulk OUT endpoint.' });
      await device.claimInterface(target.interfaceNumber);
      claimed = target.interfaceNumber;
      if (target.alternateSetting) {
        await device.selectAlternateInterface(target.interfaceNumber, target.alternateSetting);
      }
      await work(device, target);
      return answer({ ok: true });
    } catch (error) {
      return failure(classify(error), error);
    } finally {
      if (claimed !== null) {
        try {
          await withTimeout(device.releaseInterface(claimed), OPEN_TIMEOUT_MS, 'Releasing');
        } catch (_) {
          // Closing below releases it too.
        }
      }
      try {
        if (device.opened) await withTimeout(device.close(), OPEN_TIMEOUT_MS, 'Closing');
      } catch (_) {
        // The browser frees a device whose tab lets go of it.
      }
    }
  }

  function decodeBase64(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  async function choose(anyDevice) {
    if (!isSupported()) return answer({ ok: false, code: 'unsupported' });
    try {
      const device = await navigator.usb.requestDevice({
        filters: anyDevice ? [] : [{ classCode: PRINTER_CLASS }],
      });
      return answer({ ok: true, device: describe(device) });
    } catch (error) {
      // Closing the picker without choosing is `NotFoundError`, and is not a
      // failure: nothing was chosen.
      if (error && error.name === 'NotFoundError') return answer({ ok: true, device: null });
      return failure(classify(error), error);
    }
  }

  async function permitted() {
    if (!isSupported()) return answer({ ok: true, devices: [] });
    try {
      const devices = await navigator.usb.getDevices();
      return answer({ ok: true, devices: devices.map(describe) });
    } catch (error) {
      return failure(classify(error), error);
    }
  }

  function probe(key) {
    return withPrinter(key, async function () {});
  }

  function print(key, dataBase64) {
    let bytes;
    try {
      bytes = decodeBase64(dataBase64);
    } catch (error) {
      return Promise.resolve(failure('failed', error));
    }
    return withPrinter(key, async function (device, target) {
      for (let offset = 0; offset < bytes.length; offset += CHUNK_BYTES) {
        const chunk = bytes.subarray(offset, Math.min(offset + CHUNK_BYTES, bytes.length));
        const outcome = await withTimeout(
          device.transferOut(target.endpointNumber, chunk),
          WRITE_TIMEOUT_MS,
          'Sending to the printer',
        );
        if (outcome.status === 'stall') {
          try {
            await device.clearHalt('out', target.endpointNumber);
          } catch (_) {
            // The next receipt finds out whether it cleared.
          }
          throw named('NetworkError', 'The printer stalled.');
        }
        if (outcome.status !== 'ok') {
          throw named('NetworkError', 'Transfer ended ' + outcome.status + '.');
        }
      }
    });
  }

  globalThis.UzaPayUsbPrinter = Object.freeze({
    get isSupported() {
      return isSupported();
    },
    choose: choose,
    permitted: permitted,
    probe: probe,
    print: print,
  });
})();
