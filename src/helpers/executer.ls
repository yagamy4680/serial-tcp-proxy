require! <[colors fs path byline lodash]>
{spawn} = require \child_process
EventEmitter = require \events
{Parser, Generator} = require \./cmder


class Executer extends EventEmitter
  (@parent, pino, @executable, @args) ->
    self = @
    self.logger = logger = pino.child {category: "Executer"}
    self.name = name = path.basename executable
    logger.info "run #{name.yellow}, with arguments: #{JSON.stringify args}"
    args = [ a.toString! for a in args ]
    self.parser = parser = new Parser self, name, logger
    self.parser.on 'timer-req', (evt, interval) -> return self.timer_req evt, interval
    self.generator = generator = new Generator self, name, logger
    self.child = child = spawn executable, args
    self.stdout = byline child.stdout
    self.stdout.on 'data', (data) -> parser.parse_line data
    self.stderr = byline child.stderr
    self.stderr.on 'data', (line) -> logger.info " #{name}/stderr: #{line.toString!.red}"
    self.stdin = stdin = child.stdin
    child.on 'error', (err) -> logger.error err
    child.on 'close', (code) -> 
      logger.info "close: #{code}"
      return process.exit 0
    self.timers = {}
    
  feed: (chunk, channel="default") ->
    {logger, name, stdin, generator} = self = @
    data = generator.gen_data_packet chunk, channel
    stdin.write data
    return

  timer_req: (evt, interval) ->
    {logger, timers, stdin, generator} = self = @
    f = ->
      data = generator.gen_event_packet "timer-expiry", evt, interval.toString!
      stdin.write data
      logger.info "timer[#{evt}] expired in #{interval}ms"
    timers[evt] = timer = setInterval f, interval
    logger.info "start a timer #{evt.yellow} with #{interval}ms"


module.exports = exports = {Executer}
