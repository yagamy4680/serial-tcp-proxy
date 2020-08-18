SerialPort = require \serialport

module.exports = exports =
  command: "start <filepath>"
  describe: "startup a tcp proxy server on the serial port with specified path"

  builder: (yargs) ->
    yargs
      .example '$0 start /dev/tty.usbmodem1462103', 'run tcp proxy server at default port 8080, and relay the traffic of serial port at path /dev/tty.usbmodem1462103'
      .alias \p, \port
      .default \p, 8080
      .describe \p, "the port number for tcp proxy server to listen"
      .alias \b, \baud
      .default \b, 9600
      .describe \b, "baud rate for opening serial port"
      .alias \d, \databits
      .default \d, 8
      .describe \d, "data bits"
      .alias \y, \parity
      .default \y, \none
      .describe \y, "parity"
      .alias \s, \stopbits
      .default \s, 1
      .describe \s, "stop bits"
      .demand <[p b d y s]>


  handler: (argv) ->
    {config} = global
    {uart, parity, filepath} = argv
    baudRate = argv.baud
    dataBits = argv.databits
    stopBits = argv.stopbits
    opts = {baudRate, dataBits, parity, stopBits}
    SerialPort.list! .then (ports) ->
      console.dir ports
    console.log "opts => #{JSON.stringify opts}"
    console.log "argv => #{JSON.stringify argv}"
