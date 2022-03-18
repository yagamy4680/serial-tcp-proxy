EventEmitter = require \events
SerialPort = require \serialport
Recorder = require \./recorder
require! <[byline through2]>

module.exports = exports = class SerialServer extends EventEmitter
  (pino, @filepath, @baudRate=9600, @parity='none', @stopBits=1, @dataBits=8, @raw=no, @queued=no, capture) ->
    self = @
    self.data_buffer = []
    logger = @logger = pino.child {category: 'SerialServer'}
    recorder = @recorder = new Recorder self, logger, capture
    autoOpen = no
    connected = no
    opts = @opts = {autoOpen, baudRate, dataBits, parity, stopBits}
    p = @p = new SerialPort filepath, opts
    p.on \error, (err) -> return self.on_error err
    p.on \close, -> return self.on_close!
    f = -> return self.at_timer_expiry!
    setInterval f, 100ms
  
  at_timer_expiry: ->
    {data_buffer, queued} = self = @
    return unless queued
    return unless data_buffer.length > 0
    self.data_buffer = []
    chunk = Buffer.from data_buffer
    @logger.debug "emit queued data (#{(chunk.toString 'hex').toUpperCase!}), #{data_buffer.length} bytes"
    return self.emit \bytes, chunk

  emit_bytes: (chunk, immediate=yes) ->
    {recorder} = self = @
    recorder.save_data_from_serial chunk
    return self.emit \bytes, chunk if immediate
    return self.emit \bytes, chunk unless @queued
    @logger.debug "receive #{chunk.length} bytes from serial (#{(chunk.toString 'hex').toUpperCase!}) but queued"
    xs = [ x for x in chunk ]
    @data_buffer = @data_buffer ++ xs

  start_line_mode: (done) ->
    {connected, filepath, opts, p, logger} = self = @
    return if connected
    logger.info "opening #{filepath.yellow} with options: #{(JSON.stringify opts).yellow} in LINE mode ..."
    (err) <- p.open
    return done err if err?
    self.connected = yes
    logger.debug "opened"

    reader = byline.createStream!
    reader.on 'data', (line) -> return self.emit \line, line

    cb = (chunk, enc, cb) ->
      self.emit_bytes chunk
      @.push chunk
      return cb!

    ts = through2 cb
    xx = p.pipe ts .pipe reader
    return done!


  start_raw_mode: (done) ->
    {connected, filepath, opts, p, logger} = self = @
    return if connected
    logger.info "opening #{filepath.yellow} with options: #{(JSON.stringify opts).yellow} in RAW mode ..."
    (err) <- p.open
    return done err if err?
    self.connected = yes
    logger.debug "opened"
    p.on \data, (chunk) -> return self.emit_bytes chunk, no
    return done!

  start: (done) ->
    @recorder.start!
    return @.start_raw_mode done if @raw
    return @.start_line_mode done

  write: (chunk) ->
    {recorder, p} = self = @
    recorder.save_data_from_tcp chunk
    return p.write chunk

  on_error: (err) ->
    {logger, filepath} = self = @
    console.log "#{filepath}: err => #{err}"
    logger.error err
    self.emit 'error', err

  on_close: ->
    {logger, filepath} = self = @
    logger.error "#{filepath}: port is closed!!"
    self.emit 'close', {}

