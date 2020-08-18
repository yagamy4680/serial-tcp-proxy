EventEmitter = require \events
require! <[net lodash]>


class ConnectionHandler
  (@parent, @c) ->
    self = @
    @logger = parent.logger
    {remote-address, remote-family, remote-port} = c
    @remote-address = remote-address
    @remote = remote = if remote-address? and remote-port? then "#{remote-address}:#{remote-port}" else "localhost"
    @prefix = prefix = "sock[#{remote.magenta}]"
    remote-family = "unknown" unless remote-family?
    @logger.debug "#{prefix}: incoming-connection => #{remote-family.yellow}"
    c.on \end, -> return self.at_end!
    c.on \error, (err) -> return self.at_error err
    c.on \data, (data) -> return parent.at_data self, c, data

  finalize: ->
    {parent, prefix, c, logger} = self = @
    logger.info "#{prefix}: disconnected"
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
  (pino, @port=8080) ->
    self = @
    self.connections = []
    logger = @logger = pino.child {messageKey: 'TcpServer'}
    server = @server = net.createServer (c) -> return self.incomingConnection c

  start: (done) ->
    {server, port, logger} = self = @
    logger.debug "starting tcp server ..."
    (err) <- server.listen port
    return done err if err?
    logger.info "listening port #{port}"
    return done!
    
  incomingConnection: (c) ->
    {connections} = self = @
    h = new ConnectionHandler self, c
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