EventEmitter = require \events
require! <[net lodash]>


class ConnectionHandler
  (@parent, @c, queued=0) ->
    self = @
    self.logger = logger = parent.logger
    self.data_buffer = []
    self.alive = yes
    {remote-address, remote-family, remote-port} = c
    self.remote-address = remote-address
    self.remote = remote = if remote-address? and remote-port? then "#{remote-address}:#{remote-port}" else "localhost"
    self.prefix = prefix = "sock[#{remote.magenta}]"
    remote-family = "unknown" unless remote-family?
    self.logger.debug "#{prefix}: incoming-connection => #{remote-family.yellow}, with config (queued = #{queued})"
    c.on \end, -> return self.at_end!
    c.on \error, (err) -> return self.at_error err
    c.on \data, (data) -> return self.at_data data
    self.queued = queued > 0
    self.queued_interval = queued
    return unless self.queued
    f = -> return self.at_timer_expiry!
    logger.info "queued = #{self.queued_interval.toString!.yellow}ms"
    self.queued_timer = setInterval f, self.queued_interval

  at_data: (chunk) ->
    {logger, c, data_buffer, queued, alive} = self = @
    return unless alive
    return self.parent.at_data self, c, chunk unless queued
    logger.debug "receive #{chunk.length} bytes from tcp (#{(chunk.toString 'hex').toUpperCase!}) but queued"
    xs = [ x for x in chunk ]
    self.data_buffer = @data_buffer ++ xs

  at_timer_expiry: ->
    {logger, c, data_buffer, queued, alive, parent} = self = @
    return unless alive
    return unless queued
    return unless data_buffer.length > 0
    self.data_buffer = []
    chunk = Buffer.from data_buffer
    logger.debug "emit queued data (#{(chunk.toString 'hex').toUpperCase!}), #{data_buffer.length} bytes"
    return parent.at_data self, c, chunk

  finalize: ->
    {parent, prefix, c, logger, timer} = self = @
    logger.info "#{prefix}: disconnected"
    self.alive = no
    clearInterval timer
    c.removeAllListeners \error
    c.removeAllListeners \data
    c.removeAllListeners \end
    return parent.removeConnection self

  at_error: (err) ->
    {prefix, remote, logger} = self = @
    logger.error err, "#{prefix}: throws error, remove it from connnection-list, err: #{err}"
    return self.finalize!

  at_end: ->
    return @.finalize!

  write: ->
    return @c.write.apply @c, arguments

  end: ->
    return @c.end.apply @c, arguments

  destroy: ->
    return @c.destroy.apply @c, arguments



module.exports = exports = class TcpServer extends EventEmitter
  (pino, @port=8080, @queued=no) ->
    self = @
    self.connections = []
    logger = @logger = pino.child {category: 'TcpServer'}
    server = @server = net.createServer (c) -> return self.incomingConnection c

  start: (done) ->
    {server, port, logger, queued} = self = @
    logger.debug "starting tcp server ... (queued = #{queued})"
    (err) <- server.listen port
    return done err if err?
    logger.info "listening port #{port}"
    return done!
    
  incomingConnection: (c) ->
    {connections, queued} = self = @
    h = new ConnectionHandler self, c, queued
    return connections.push h

  removeConnection: (h) ->
    {connections, prefix, logger} = self = @
    {remote} = h
    idx = lodash.findIndex connections, h
    logger.warn "disconnected, and remove #{remote.magenta} from slots[#{idx}]"
    return connections.splice idx, 1 if idx?

  at_data: (h, c, data) ->
    return @.emit \data, data, c

  broadcast: (chunk) ->
    {connections} = self = @
    [ (c.write chunk) for c in connections ]

