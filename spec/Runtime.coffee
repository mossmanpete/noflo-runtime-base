noflo = require 'noflo'

if noflo.isBrowser()
  direct = require('noflo-runtime-base').direct
  baseDir = 'noflo-runtime-base'
else
  chai = require 'chai' unless chai
  direct = require '../src/direct'
  path = require 'path'
  baseDir = path.resolve __dirname, '../'

describe 'Runtime protocol', ->
  runtime = null
  client = null

  describe 'sending runtime:getruntime', ->
    beforeEach ->
      runtime = new direct.Runtime
      client = new direct.Client runtime
      client.connect()
    afterEach ->
      client.disconnect()
      client = null
      runtime = null
    it 'should respond with runtime:runtime for unauthorized user', (done) ->
      client.once 'message', (msg) ->
        chai.expect(msg.protocol).to.equal 'runtime'
        chai.expect(msg.command).to.equal 'runtime'
        chai.expect(msg.payload.type).to.have.string 'noflo'
        chai.expect(msg.payload.capabilities).to.eql []
        chai.expect(msg.payload.allCapabilities).to.include 'protocol:graph'
        done()
      client.send 'runtime', 'getruntime', null
    it 'should respond with runtime:runtime for authorized user', (done) ->
      client.disconnect()
      runtime = new direct.Runtime
        permissions:
          'super-secret': ['protocol:graph', 'protocol:component', 'unknown:capability']
          'second-secret': ['protocol:graph', 'protocol:runtime']
      client = new direct.Client runtime
      client.connect()
      client.once 'message', (msg) ->
        chai.expect(msg.protocol).to.equal 'runtime'
        chai.expect(msg.command).to.equal 'runtime'
        chai.expect(msg.payload.type).to.have.string 'noflo'
        chai.expect(msg.payload.capabilities).to.eql ['protocol:graph', 'protocol:component']
        chai.expect(msg.payload.allCapabilities).to.include 'protocol:graph'
        done()
      client.send 'runtime', 'getruntime',
        secret: 'super-secret'
  describe 'with a graph containing exported ports', ->
    before ->
      runtime = new direct.Runtime
        permissions:
          'second-secret': ['protocol:graph', 'protocol:runtime', 'protocol:network']
        baseDir: baseDir
      client = new direct.Client runtime
      client.connect()
    after ->
      client.disconnect()
      client = null
      runtime = null
      runtime = new direct.Runtime
    it 'should be possible to upload graph', (done) ->
      client.on 'error', (err) ->
        done err
      client.on 'message', (msg) ->
        if msg.command is 'error'
          return done msg.payload
        return unless msg.command is 'addoutport'
        done()
      client.send 'graph', 'clear',
        id: 'bar'
        main: true
        secret: 'second-secret'
      client.send 'graph', 'addnode',
        id: 'Hello'
        component: 'core/Repeat'
        graph: 'bar'
        secret: 'second-secret'
      client.send 'graph', 'addnode',
        id: 'World'
        component: 'core/Repeat'
        graph: 'bar'
        secret: 'second-secret'
      client.send 'graph', 'addedge',
        src:
          node: 'Hello'
          port: 'out'
        tgt:
          node: 'World'
          port: 'in'
        graph: 'bar'
        secret: 'second-secret'
      client.send 'graph', 'addinport',
        public: 'in'
        node: 'Hello'
        port: 'in'
        graph: 'bar'
        secret: 'second-secret'
      client.send 'graph', 'addoutport',
        public: 'in'
        node: 'Hello'
        port: 'out'
        graph: 'bar'
        secret: 'second-secret'
    it 'should be possible to start the network', (done) ->
      client.on 'error', (err) ->
        done err
      client.on 'message', (msg) ->
        return unless msg.command is 'started'
        done()
      client.send 'network', 'start',
        graph: 'bar'
        secret: 'second-secret'
    it 'packets sent to IN should be received at OUT', (done) ->
      payload =
        hello: 'World'
      client.on 'error', (err) ->
        done err
      client.on 'message', (msg) ->
        return unless msg.protocol is 'runtime'
        return unless msg.command is 'packet'
        return unless msg.payload.event is 'data'
        chai.expect(msg.payload.payload).to.eql payload
        done()
      client.send 'runtime', 'packet',
        graph: 'bar'
        port: 'in'
        event: 'data'
        payload: payload
        secret: 'second-secret'
