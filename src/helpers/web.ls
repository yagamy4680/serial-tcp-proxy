EventEmitter = require \events
SocketIo = require \socket.io
require! <[express http path lodash]>


class ConnectionHandler
  (@parent, @c) ->
    self = @
    {filepath, serialOpts} = parent
    @logger = parent.logger
    @logger.info "incoming socket.io connection ..."
    c.on \disconnect, -> return parent.removeConnection self
    c.emit \setup, filepath, serialOpts

  write: (chunk) ->
    return @c.emit 'data', chunk


module.exports = exports = class WebServer extends EventEmitter
  (pino, @port=8081, @assetDir="#{__dirname}/../../assets/default", @filepath="ttyXXX", @serialOpts={}) ->
    self = @
    self.connections = []
    self.assetDir = path.resolve self.assetDir
    logger = @logger = pino.child {messageKey: 'WebServer'}
    logger.info "assetDir => #{self.assetDir}"
    app = @app = express!
    app.use '/', express.static "#{self.assetDir}/web", {index: <[index.html index.htm]>}
    server = @server = http.createServer app
    io = @io = SocketIo server
    channel = @channel = io.of '/serial'
    channel.on 'connection', (c) -> return self.incomingConnection c

  start: (done) ->
    {server, port, logger, assetDir} = self = @
    logger.debug "starting web server ..."
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
    logger.warn "disconnected, and removed from slots[#{idx}]"
    return connections.splice idx, 1 if idx?

  broadcast: (chunk) ->    
    {connections} = self = @
    [ (c.write chunk) for c in connections ]
