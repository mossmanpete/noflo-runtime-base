/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
module.exports = function() {
  // Project configuration
  this.initConfig({
    pkg: this.file.readJSON('package.json'),

    // CoffeeScript compilation
    coffee: {
      src: {
        options: {
          bare: true
        },
        expand: true,
        cwd: 'src',
        src: ['**.coffee'],
        dest: '',
        ext: '.js'
      },
      protocol: {
        options: {
          bare: true
        },
        expand: true,
        cwd: 'src/protocol',
        src: ['**.coffee'],
        dest: 'protocol',
        ext: '.js'
      },
      spec: {
        options: {
          transpile: {
            presets: ['es2015']
          },
          bare: true
        },
        expand: true,
        cwd: 'spec',
        src: ['**.coffee'],
        dest: 'spec',
        ext: '.js'
      }
    },

    // Browser version building
    noflo_browser: {
      build: {
        options: {
          exposed_modules: {
            noflo: 'noflo',
            'noflo-runtime-base': './Base.js'
          }
        },
        files: {
          'browser/noflo-runtime-base.js': ['component.json']
        }
      }
    },

    // Automated recompilation and testing when developing
    watch: {
      files: ['spec/*.coffee', 'src/*.coffee', 'src/**/*.coffee'],
      tasks: ['test']
    },

    // BDD tests on Node.js
    mochaTest: {
      nodejs: {
        src: ['spec/*.coffee'],
        options: {
          reporter: 'spec'
        }
      }
    },

    // Generate runner.html
    noflo_browser_mocha: {
      all: {
        options: {
          scripts: ["../browser/<%=pkg.name%>.js"]
        },
        files: {
          'spec/runner.html': ['spec/*.js']
        }
      }
    },
    // BDD tests on browser
    mocha_phantomjs: {
      options: {
        output: 'spec/result.xml',
        reporter: 'spec',
        failWithOutput: true
      },
      all: ['spec/runner.html']
    },

    // Coding standards
    coffeelint: {
      src: {
        files: {
          src: ['src/*.coffee', 'src/**/*.coffee']
        },
        options: {
          max_line_length: {
            value: 120,
            level: 'warn'
          }
        }
      }
    }
  });

  // Grunt plugins used for building
  this.loadNpmTasks('grunt-contrib-coffee');
  this.loadNpmTasks('grunt-noflo-browser');

  // Grunt plugins used for testing
  this.loadNpmTasks('grunt-contrib-watch');
  this.loadNpmTasks('grunt-mocha-test');
  this.loadNpmTasks('grunt-mocha-phantomjs');
  this.loadNpmTasks('grunt-coffeelint');

  // Our local tasks
  this.registerTask('build', 'Build NoFlo for the chosen target platform', target => {
    if (target == null) { target = 'all'; }
    if ((target === 'all') || (target === 'nodejs')) {
      this.task.run('coffee:src');
      this.task.run('coffee:protocol');
    }
    if ((target === 'all') || (target === 'browser')) {
      return this.task.run('noflo_browser');
    }
  });

  this.registerTask('test', 'Build NoFlo and run automated tests', target => {
    if (target == null) { target = 'all'; }
    this.task.run('coffeelint');
    this.task.run('build');
    if ((target === 'all') || (target === 'nodejs')) {
      this.task.run('mochaTest');
    }
    if ((target === 'all') || (target === 'browser')) {
      this.task.run('coffee:spec');
      this.task.run('noflo_browser_mocha');
      return this.task.run('mocha_phantomjs');
    }
  });

  return this.registerTask('default', ['test']);
};
