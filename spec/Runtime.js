/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let baseDir, chai, direct;
const noflo = require('noflo');

if (noflo.isBrowser()) {
  ({
    direct
  } = require('noflo-runtime-base'));
  baseDir = 'noflo-runtime-base';
} else {
  if (!chai) { chai = require('chai'); }
  direct = require('../direct');
  const path = require('path');
  baseDir = path.resolve(__dirname, '../');
}

describe('Runtime protocol', function() {
  let runtime = null;
  let client = null;

  describe('sending runtime:getruntime', function() {
    beforeEach(function() {
      runtime = new direct.Runtime;
      client = new direct.Client(runtime);
      return client.connect();
    });
    afterEach(function() {
      client.disconnect();
      client = null;
      return runtime = null;
    });
    it('should respond with runtime:runtime for unauthorized user', function(done) {
      client.once('message', function(msg) {
        chai.expect(msg.protocol).to.equal('runtime');
        chai.expect(msg.command).to.equal('runtime');
        chai.expect(msg.payload.type).to.have.string('noflo');
        chai.expect(msg.payload.capabilities).to.eql([]);
        chai.expect(msg.payload.allCapabilities).to.include('protocol:graph');
        return done();
      });
      return client.send('runtime', 'getruntime', null);
    });
    return it('should respond with runtime:runtime for authorized user', function(done) {
      client.disconnect();
      runtime = new direct.Runtime({
        permissions: {
          'super-secret': ['protocol:graph', 'protocol:component', 'unknown:capability'],
          'second-secret': ['protocol:graph', 'protocol:runtime']
        }});
      client = new direct.Client(runtime);
      client.connect();
      client.once('message', function(msg) {
        chai.expect(msg.protocol).to.equal('runtime');
        chai.expect(msg.command).to.equal('runtime');
        chai.expect(msg.payload.type).to.have.string('noflo');
        chai.expect(msg.payload.capabilities).to.eql(['protocol:graph', 'protocol:component']);
        chai.expect(msg.payload.allCapabilities).to.include('protocol:graph');
        return done();
      });
      return client.send('runtime', 'getruntime',
        {secret: 'super-secret'});
    });
  });
  return describe('with a graph containing exported ports', function() {
    let ports = null;
    before(function() {
      runtime = new direct.Runtime({
        permissions: {
          'second-secret': ['protocol:graph', 'protocol:runtime', 'protocol:network']
        },
        baseDir
      });
      client = new direct.Client(runtime);
      return client.connect();
    });
    after(function() {
      client.disconnect();
      client = null;
      runtime = null;
      runtime = new direct.Runtime;
      return ports = null;
    });
    it('should be possible to upload graph', function(done) {
      client.on('error', err => done(err));
      client.on('message', function(msg) {
        if (msg.command === 'error') {
          return done(msg.payload);
        }
        if (msg.command !== 'addoutport') { return; }
        return done();
      });
      client.send('graph', 'clear', {
        id: 'bar',
        main: true,
        secret: 'second-secret'
      }
      );
      client.send('graph', 'addnode', {
        id: 'Hello',
        component: 'core/Repeat',
        graph: 'bar',
        secret: 'second-secret'
      }
      );
      client.send('graph', 'addnode', {
        id: 'World',
        component: 'core/Repeat',
        graph: 'bar',
        secret: 'second-secret'
      }
      );
      client.send('graph', 'addedge', {
        src: {
          node: 'Hello',
          port: 'out'
        },
        tgt: {
          node: 'World',
          port: 'in'
        },
        graph: 'bar',
        secret: 'second-secret'
      }
      );
      client.send('graph', 'addinport', {
        public: 'in',
        node: 'Hello',
        port: 'in',
        graph: 'bar',
        secret: 'second-secret'
      }
      );
      return client.send('graph', 'addoutport', {
        public: 'out',
        node: 'World',
        port: 'out',
        graph: 'bar',
        secret: 'second-secret'
      }
      );
    });
    it('should be possible to start the network', function(done) {
      client.on('error', err => done(err));
      client.on('message', function(msg) {
        if (msg.protocol !== 'network') { return; }
        if (msg.command !== 'started') { return; }
        return done();
      });
      runtime.runtime.on('ports', emittedPorts => ports = emittedPorts);
      return client.send('network', 'start', {
        graph: 'bar',
        secret: 'second-secret'
      }
      );
    });
    it('packets sent to IN should be received at OUT', function(done) {
      const payload =
        {hello: 'World'};
      client.on('error', err => done(err));
      var messageListener = function(msg) {
        if (msg.protocol !== 'runtime') { return; }
        if (msg.command !== 'packet') { return; }
        if (msg.payload.port !== 'out') { return; }
        if (msg.payload.event !== 'data') { return; }
        chai.expect(msg.payload.payload).to.eql(payload);
        client.removeListener('message', messageListener);
        return done();
      };
      client.on('message', messageListener);
      return client.send('runtime', 'packet', {
        graph: 'bar',
        port: 'in',
        event: 'data',
        payload,
        secret: 'second-secret'
      }
      );
    });
    it('should have emitted ports via JS API', function() {
      chai.expect(ports.inPorts.length).to.equal(1);
      return chai.expect(ports.outPorts.length).to.equal(1);
    });
    return it('packets sent via JS API to IN should be received at OUT', function(done) {
      const payload =
        {hello: 'JavaScript'};
      runtime.runtime.on('packet', function(msg) {
        if (msg.event !== 'data') { return; }
        chai.expect(msg.payload).to.eql(payload);
        return done();
      });
      return runtime.runtime.sendPacket({
        graph: 'bar',
        port: 'in',
        event: 'data',
        payload,
        secret: 'second-secret'
      }
      , function(err) {
        if (err) { return done(err); }
      });
    });
  });
});
