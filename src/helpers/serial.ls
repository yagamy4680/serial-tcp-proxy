EventEmitter = require \events
SerialPort = require \serialport
require! <[byline through2]>

module.exports = exports = class SerialServer extends EventEmitter
  (pino, @filepath, @baudRate=9600, @parity='none', @stopBits=1, @dataBits=8) ->
    self = @
    logger = @logger = pino.child {messageKey: 'SerialServer'}
    autoOpen = no
    connected = no
    opts = @opts = {autoOpen, baudRate, dataBits, parity, stopBits}
    p = @p = new SerialPort filepath, opts
    p.on \error, (err) -> return self.on_error err
    # p.on 'data', (data) -> return self.on_serial_data data

  start: (done) ->
    {connected, filepath, opts, p, logger} = self = @
    return if connected
    logger.info "opening #{filepath.yellow} with options: #{(JSON.stringify opts).yellow} ..."
    (err) <- p.open
    return done err if err?
    self.connected = yes
    logger.debug "opened"

    reader = byline.createStream!
    reader.on 'data', (line) -> return self.emit \line, line

    cb = (chunk, enc, cb) ->
      self.emit \bytes, chunk
      @.push chunk
      return cb!

    ts = through2 cb
    xx = p.pipe ts .pipe reader
    return done!

  write: (chunk) ->
    return @p.write chunk

  on_error: (err) ->
    console.log "err => #{err}"
    @.logger.error err
