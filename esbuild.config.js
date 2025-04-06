const esbuild = require('esbuild');

// Define the build options
const buildOptions = {
  entryPoints: ['app/javascript/application.js'],
  bundle: true,
  outdir: 'app/assets/builds',
  sourcemap: true,
  format: 'iife',
  loader: {
    '.js': 'jsx',
    '.jsx': 'jsx'
  },
  define: {
    'process.env.NODE_ENV': '"development"'
  },
  minify: false,
  target: ['es2020'],
  jsxFactory: 'React.createElement',
  jsxFragment: 'React.Fragment'
};

// Handle build or watch mode
if (process.argv.includes('--watch')) {
  esbuild.context(buildOptions)
    .then(ctx => {
      ctx.watch();
      console.log('Watching for changes...');
    })
    .catch(() => process.exit(1));
} else {
  esbuild.build(buildOptions)
    .catch(() => process.exit(1));
}