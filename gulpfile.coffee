_ = require "underscore"
$ = require("gulp-load-plugins")()
gulp = require "gulp"
path = require "path"
rename = require "gulp-rename"
merge = require "merge-stream"
deepExtend = require "deep-extend"
runSequence = require "run-sequence"
autoprefixer = require "autoprefixer"
log = require "fancy-log"
PluginError = require "plugin-error"

webpack = require "webpack"
WebpackDevServer = require "webpack-dev-server"

####################
## CONFIG
####################

config =
  paths:
    app: "app"
    tmp: ".tmp"
    dist: "dist"
    scripts: "app/scripts"
    styles: "app/styles"
    assets: "app/assets"

  serverPort: 9000

  webpack: ->
    resolveLoader:
      modules: ["node_modules"]

    output:
      path: path.join __dirname, config.paths.tmp
      filename: "bundle.js"
      publicPath: "/"

    resolve:
      extensions: [".js", ".coffee", ".scss", ".css", ".ttf"]
      alias:
        "assets": path.join __dirname, config.paths.assets

    module:
      rules: [
        { test: /\.scss$/, use: ["style-loader", "css-loader", "postcss-loader", "sass-loader"] }
        { test: /\.coffee$/, use: ["coffee-loader"] }
        { test: /\.png/, type: "asset/inline", generator: { dataUrl: { mimetype: "image/png" } } }
        { test: /\.ttf/, type: "asset/inline", generator: { dataUrl: { mimetype: "font/ttf" } } }
      ]

  webpackEnvs: ->
    development:
      mode: "development"
      devtool: "eval"
      entry: [
        "./#{config.paths.scripts}/app"
      ]

      plugins: [
        new webpack.HotModuleReplacementPlugin
      ]

    distribute:
      mode: "production"
      entry: [
        "./#{config.paths.scripts}/app"
      ]

      optimization:
        minimize: true

config = _(config).mapObject (val) ->
  if _.isFunction(val) then val() else val

# Function to create webpack compiler with merged config
getWebpackCompiler = (envName) ->
  val = config.webpackEnvs[envName]
  # Merge configs manually to avoid deepExtend corrupting plugin objects
  mergedConfig = Object.assign({}, config.webpack)
  for key, value of val
    if key is 'plugins'
      # For plugins, use the value from env config (contains plugin instances)
      mergedConfig[key] = value
    else if key is 'module' or key is 'resolve'
      # For module and resolve, deep merge but preserve existing values
      if value
        mergedConfig[key] = Object.assign({}, mergedConfig[key] or {}, value)
    else if typeof value is 'object' and not Array.isArray(value)
      mergedConfig[key] = Object.assign({}, mergedConfig[key] or {}, value)
    else
      mergedConfig[key] = value
  webpack mergedConfig

####################
## TASKS
####################

gulp.task "copy-assets", (done) ->
  gulp
    .src path.join(config.paths.assets, "**"), { encoding: false }
    .pipe gulp.dest("#{config.paths.tmp}/assets")
    .on 'end', ->
      gulp
        .src path.join(config.paths.app, "index.html")
        .pipe gulp.dest(config.paths.tmp)
        .on 'end', done

gulp.task "copy-page-files", ->
  gulp
    .src path.join(config.paths.assets, "{instructions.html,page.png,result.html,beach.jpg}")
    .pipe gulp.dest(path.join config.paths.dist, "assets")

gulp.task "webpack-dev-server", ->
  log "Creating webpack compiler..."
  compiler = getWebpackCompiler('development')
  log "Compiler created, starting dev server..."
  server = new WebpackDevServer {
    static:
      directory: config.paths.tmp
      publicPath: "/"
    hot: true
    port: config.serverPort
    host: "0.0.0.0"
    client:
      logging: "warn"
  }, compiler

  # Return a promise that keeps the task running
  server.start().then ->
    log "[webpack-dev-server] Server running on http://localhost:#{config.serverPort}"
    # Return a promise that never resolves to keep the server running
    new Promise (resolve) -> # Never call resolve
  .catch (err) ->
    log.error "Error starting webpack-dev-server:", err
    throw err

gulp.task "build", (done) ->
  compiler = getWebpackCompiler('distribute')
  compiler.run (err, stats) ->
    if err
      throw new PluginError("webpack:build", err)
    if stats.hasErrors()
      throw new PluginError("webpack:build", "Build failed with errors")
    done()

watchAssets = (done) ->
  gulp.watch ["app/assets/**"], gulp.series("copy-assets")
  done()

gulp.task "serve", gulp.series("copy-assets", "webpack-dev-server", watchAssets)

gulp.task "inline", ->
  gulp
    .src "#{config.paths.tmp}/index.html"
    .pipe $.inlineSource()
    .pipe rename(basename: "editor")
    .pipe gulp.dest("#{config.paths.dist}")

gulp.task "dist", gulp.series("copy-assets", "build", "inline", "copy-page-files")

gulp.task "default", gulp.series("serve")
