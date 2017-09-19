noflo = require 'noflo'
EventEmitter = require('events').EventEmitter

prepareSocketEvent = (event, req) ->
  payload =
    id: event.id
    graph: req.graph
  if event.socket.from
    payload.src =
      node: event.socket.from.process.id
      port: event.socket.from.port
  if event.socket.to
    payload.tgt =
      node: event.socket.to.process.id
      port: event.socket.to.port
  if event.subgraph
    payload.subgraph = event.subgraph
  if event.group
    payload.group = event.group
  if event.datatype
    payload.type = event.datatype
  if event.schema
    payload.schema = event.schema
  if typeof event.data isnt 'undefined'
    unless noflo.isBrowser()
      if Buffer.isBuffer event.data
        # Make sure we're not trying to serialize the whole buffer to JSON
        event.data = event.data.slice 0, 20
    if event.data.toJSON
      payload.data = event.data.toJSON()
    if event.data.toString
      payload.data = event.data.toString()
      if payload.data is '[object Object]'
        try
          payload.data = JSON.parse JSON.stringify event.data
    else
      payload.data = event.data

    if event.metadata?.secure
      # Don't send actual payload for private connections
      payload.data = 'DATA'
  payload

getPortSignature = (item) ->
  return '' unless item
  return item.process + '(' + item.port + ')'

getEdgeSignature = (edge) ->
  return getPortSignature(edge.src) + ' -> ' + getPortSignature(edge.tgt)

getConnectionSignature = (connection) ->
  return '' unless connection
  return connection.process.id + '(' + connection.port + ')'

getSocketSignature = (socket) ->
  return getConnectionSignature(socket.from) +  ' -> ' + getConnectionSignature(socket.to)

class NetworkProtocol extends EventEmitter
  constructor: (@transport) ->
    @networks = {}

  send: (topic, payload, context) ->
    @transport.send 'network', topic, payload, context

  sendAll: (topic, payload) ->
    @transport.sendAll 'network', topic, payload

  receive: (topic, payload, context) ->
    unless @transport.canDo 'protocol:network', payload.secret
      @send 'error', new Error("#{topic} not permitted"), context
      return

    if topic isnt 'list'
      graph = @resolveGraph payload, context
      return unless graph

    switch topic
      when 'start'
        @startNetwork graph, payload, context
      when 'stop'
        @stopNetwork graph, payload, context
      when 'edges'
        @updateEdgesFilter graph, payload, context
      when 'debug'
        @debugNetwork graph, payload, context
      when 'getstatus'
        @getStatus graph, payload, context

  resolveGraph: (payload, context) ->
    unless payload.graph
      @send 'error', new Error('No graph specified'), context
      return
    unless @transport.graph.graphs[payload.graph]
      @send 'error', new Error('Requested graph not found'), context
      return
    return @transport.graph.graphs[payload.graph]

  updateEdgesFilter: (graph, payload, context) ->
    network = @networks[payload.graph]
    if network
      network.filters = {}
    else
      network =
        network: null
        filters: {}
      @networks[payload.graph] = network

    for edge in payload.edges
      signature = getEdgeSignature(edge)
      network.filters[signature] = true
    @send 'edges',
      graph: payload.graph
      edges: payload.edges
    , context

  eventFiltered: (graph, event) ->
    return true unless @transport.options.filterData
    sign = getSocketSignature(event.socket)
    return @networks[graph].filters[sign]

  initNetwork: (graph, payload, context, callback) ->
    # Ensure we stop previous network
    if @networks[payload.graph] and @networks[payload.graph].network
      network = @networks[payload.graph].network
      network.stop (err) =>
        return callback err if err
        delete @networks[payload.graph]
        @emit 'removenetwork', network, payload.graph, @networks
        @initNetwork graph, payload, context, callback
      return

    graph.componentLoader = @transport.component.getLoader graph.baseDir, @transport.options
    opts = JSON.parse JSON.stringify @transport.options
    opts.delay = true
    noflo.createNetwork graph, (err, network) =>
      return callback err if err
      if @networks[payload.graph] and @networks[payload.graph].network
        @networks[payload.graph].network = network
      else
        @networks[payload.graph] =
          network: network
          filters: {}
      @emit 'addnetwork', network, payload.graph, @networks
      @subscribeNetwork network, payload, context

      # Run the network
      network.connect callback
    , opts

  subscribeNetwork: (network, payload, context) ->
    network.on 'start', (event) =>
      @sendAll 'started',
        time: event.start
        graph: payload.graph
        running: network.isRunning()
        started: network.isStarted()
      , context
    network.on 'end', (event) =>
      @sendAll 'stopped',
        time: new Date
        uptime: event.uptime
        graph: payload.graph
        running: network.isRunning()
        started: network.isStarted()
      , context
    network.on 'icon', (event) =>
      event.graph = payload.graph
      @sendAll 'icon', event, context
    network.on 'connect', (event) =>
      return unless @eventFiltered(payload.graph, event)
      @sendAll 'connect', prepareSocketEvent(event, payload), context
    network.on 'ip', (event) =>
      return unless @eventFiltered(payload.graph, event)
      protocolEvent =
        id: event.id
        socket: event.socket
        subgraph: event.subgraph
        metadata: event.metadata
      switch event.type
        when 'openBracket'
          protocolEvent.type = 'begingroup'
          protocolEvent.group = event.data
        when 'data'
          protocolEvent.type = 'data'
          protocolEvent.data = event.data
          protocolEvent.datatype = event.datatype
          protocolEvent.schema = event.schema
        when 'closeBracket'
          protocolEvent.type = 'endgroup'
          protocolEvent.group = event.data
      @sendAll protocolEvent.type, prepareSocketEvent(protocolEvent, payload), context
    network.on 'disconnect', (event) =>
      return unless @eventFiltered(payload.graph, event)
      @sendAll 'disconnect', prepareSocketEvent(event, payload), context

    network.on 'process-error', (event) =>
      error = event.error.message
      # If we can get a backtrace, send 3 levels
      if event.error.stack
        bt = event.error.stack.split '\n'
        for i in [0..Math.min bt.length, 3]
          error += "\n#{bt[i]}"
      @sendAll 'processerror',
        id: event.id
        error: error
        graph: payload.graph
      , context

  startNetwork: (graph, payload, context) ->
    doStart = (net) =>
      net.start (err) =>
        return @send 'error', err, content if err
    network = @networks[payload.graph]
    if network and network.network
      # already initialized
      doStart network.network
      return

    @initNetwork graph, payload, context, (err) =>
      return @send 'error', err, context if err
      network = @networks[payload.graph]
      doStart network.network

  stopNetwork: (graph, payload, context) ->
    return unless @networks[payload.graph]
    net = @networks[payload.graph].network
    return unless net
    if net.isStarted()
      @networks[payload.graph].network.stop (err) =>
        return @send 'error', err, context if err
      return
    # Was already stopped, just send the confirmation
    @send 'stopped',
      time: new Date
      graph: payload.graph
      running: net.isRunning()
      started: net.isStarted()
    , context

  debugNetwork: (graph, payload, context) ->
    return unless @networks[payload.graph]
    net = @networks[payload.graph].network
    return unless net
    if net.setDebug?
      net.setDebug payload.enable
    else
      console.log 'Warning: Network.setDebug not supported. Update to newer NoFlo'

  getStatus: (graph, payload, context) ->
    return unless @networks[payload.graph]
    net = @networks[payload.graph].network
    return unless net
    @send 'status',
        graph: payload.graph
        running: net.isRunning()
        started: net.isStarted()
    , context

module.exports = NetworkProtocol
