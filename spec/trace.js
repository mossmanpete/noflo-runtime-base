describe('Tracer', () => {
  let tracer = null;

  describe.skip('attached to Noflo.Component', () => {
    let component = null;
    const trace = null;

    before(function (done) {
      this.timeout(20 * 1000);
      console.log('before', Tracer);
      tracer = new Tracer();
      const loader = new noflo.ComponentLoader(baseDir);
      loader.load('noflo-runtime-base/TestRepeats')
        .then((instance) => {
          component = instance;
          component.once('ready', () => {
            tracer.attach(instance.network);
            setTimeout(done, 1);
          });
        }, done);
    });

    after(function (done) {
      this.timeout(10 * 1000);
      return done();
    });

    it('should collect data coming through', (done) => {
      component.once('stop', () => {
        tracer.dumpString((err, f) => {
          if (err) { return done(err); }
        });
        console.log('Wrote flowtrace to', f);
        return done();
      });

      return component.start();
    });

    it('trace should contain graph');

    it('trace should contain subgraphs');

    it('trace should have data events');

    it('trace should have groups events');

    it('trace should have data send from exported outport');

    return it('trace should have data send to exported inport');
  });

  return describe('tracing unserializable events', () => it('should drop only those events'));
});

describe('FBP protocol tracing', () => // TODO: https://github.com/noflo/noflo-runtime-base/issues/36
  describe(
    'runtime with trace=true',
    () => describe('triggering trace', () => it('should return trace')),
  ));
