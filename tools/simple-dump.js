const colors = require('colors');
const yargs = require('yargs');
const io = require('socket.io-client');


/**
 * 1. Connect to WebSocket server as client, with given `host` and `port`. Note, the channel is always `/serial`.
 * 2. Listen to `from_serial`, `to_serial`, and `status` events, and dump them to console.
 * 3. The `host` and `port` are given as command line arguments, parsed by yargs library.
 */

function hexDump(buffer, prefix = null, color = 'white') {
  const bytesPerLine = 16;
  const spaces = prefix ? prefix.length + 4 : 0;
  const space_chars = ' '.repeat(spaces);

  for (let i = 0; i < buffer.length; i += bytesPerLine) {
    const slice = buffer.slice(i, i + bytesPerLine);
    const hex = Array.from(slice)
      .map(b => b.toString(16).padStart(2, '0'))
      .join(' ');
    const ascii = Array.from(slice)
      .map(b => (b >= 32 && b <= 126 ? String.fromCharCode(b) : '.'))
      .join('');
    let ts = (new Date()).toISOString().substring(11);
    let tokens = [];
    if (i === 0) {
      tokens.push(ts.gray);
      if (prefix) {
        tokens.push(prefix.blue);
      }
    }
    else {
      tokens.push(space_chars);
    }
    tokens.push(i.toString(16).padStart(4, '0'));
    tokens.push(' ');
    tokens.push(hex.padEnd(bytesPerLine * 3)[color]);
    tokens.push(ascii.gray);
    let text = tokens.join(' ');
    console.log(text);
  }
}


// Parse command line arguments
const argv = yargs()
  .option('host', {
    alias: 'h',
    describe: 'WebSocket server host',
    demandOption: true,
    type: 'string',
    default: 'localhost'
  })
  .option('port', {
    alias: 'p',
    describe: 'WebSocket server port',
    demandOption: true,
    type: 'number'
  })
  .help()
  .parse(process.argv.slice(2));

// Build WebSocket URL
const url = `ws://${argv.host}:${argv.port}/serial`;

// Connect to WebSocket server
const socket = io(url);

let uart = 'unknown';

// Listen and dump events to console
socket.on('connect', () => {
  console.log(`Connected to ${url}`);
});

socket.on('from_serial', (data) => {
  let { chunk } = data;
  let bytes = Buffer.from(chunk, 'base64');
  let direction = `->`;
  hexDump(bytes, `${uart} ${direction.green}`, 'green');
  console.log('');
});

socket.on('to_serial', (data) => {
  let { chunk } = data;
  let bytes = Buffer.from(chunk, 'base64');
  let direction = `<-`;
  hexDump(bytes, `${uart} ${direction.red}`, 'red');
  console.log('');
});

socket.on('status', (data) => {
  // console.log('[status]', data);
  uart = data.uart || uart;
});

socket.on('disconnect', () => {
  console.log('Disconnected');
});

socket.on('connect_error', (err) => {
  console.error('Connection error:', err.message);
});
