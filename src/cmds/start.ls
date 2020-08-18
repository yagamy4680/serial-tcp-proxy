SerialPort = require \serialport
SerialServer = require \../helpers/serial
require! <[pino]>



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
      .alias \v, \verbose
      .default \v, no
      .describe \v, "verbose output"
      .boolean 'v'
      .demand <[p b d y s v]>


  handler: (argv) ->
    {config} = global
    {uart, parity, filepath, verbose} = argv
    baudRate = argv.baud
    dataBits = argv.databits
    stopBits = argv.stopbits
    console.log "verbose = #{verbose}"
    opts = {baudRate, dataBits, parity, stopBits}
    level = if verbose then 'trace' else 'info'
    prettyPrint = translateTime: yes
    console.log "prettyPrint => #{JSON.stringify prettyPrint}"
    logger = pino {prettyPrint, level}
    (ports) <- SerialPort.list! .then
    xs = [ x for x in ports when x.path is filepath ]
    return logger.error "no such port: #{filepath}" unless xs.length >= 1
    xs = xs.pop!
    logger.debug "found #{filepath.yellow} => #{JSON.stringify xs}"
    ss = new SerialServer logger, filepath, baudRate, parity, stopBits, dataBits
    ss.on \bytes, (chunk) -> logger.debug "receive #{chunk.length} bytes (#{(chunk.toString 'hex').toUpperCase!})"
    ss.on \line, (line) -> logger.info "#{filepath.yellow}: #{line}"
    (err) <- ss.start
    return logger.debug err if err?