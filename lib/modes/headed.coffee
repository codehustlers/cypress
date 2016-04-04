_        = require("lodash")
os       = require("os")
app      = require("electron").app
image    = require("electron").nativeImage
Promise  = require("bluebird")
cyIcons  = require("@cypress/core-icons")
Position = require("electron-positioner")
notifier = require("node-notifier")
user     = require("../user")
errors   = require("../errors")
Updater  = require("../updater")
logs     = require("../electron/handlers/logs")
Tray     = require("../electron/handlers/tray")
Events   = require("../electron/handlers/events")
Renderer = require("../electron/handlers/renderer")

module.exports = {
  isMac: ->
    os.platform() is "darwin"

  onDrop: ->

  onClick: (bounds, win) ->
    positioner = new Position(win)

    coords = positioner.calculate("trayCenter", bounds)

    ## store the coords on updater
    Updater.setCoords(coords)

    win.setPosition(coords.x, coords.y)

    if win.isVisible()
      win.hide()
    else
      win.show()

  onRightClick: ->

  onWindowAllClosed: (app) ->
    ## stop all the events
    Events.stop()

    ## exit when all windows are closed
    app.exit(0)

  getRendererArgs: (coords) ->
    common = {
      width: 300
      height: 400
      resizable: false
      type: "INDEX"
      onBlur: ->
        return if @webContents.isDevToolsOpened()

        Renderer.hideAllUnlessAnotherWindowIsFocused()
      onFocus: ->
        Renderer.showAll()
    }

    _.extend(common, @platformArgs())

    ## if we have coordinates automatically add them
    if coords
      ## and also set show to true
      _.extend(common, coords, {show: true})

    return common

  platformArgs: ->
    {
      darwin: {
        show:        false
        frame:       false
        transparent: true
      }

      linux: {
        show:        true
        frame:       true
        transparent: false
        icon: image.createFromPath(cyIcons.getPathToIcon("icon_128x128.png"))
      }
    }[os.platform()]

  notify: ->
    ## bail if we aren't on mac
    return if not @isMac()

    user.ensureSession()
    .catch ->
      notifier.notify({
        # subtitle:
        title: "Cypress is now running..."
        message: "Click the 'cy' icon in your tray to login."
        icon: cyIcons.getPathToIcon("icon_32x32@2x.png")
      })

  ready: (options = {}) ->
    options.app = app

    ready = =>
      ## TODO:
      ## handle right click to show context menu!
      ## handle drop events for automatically adding projects!
      ## use the same icon as the cloud app
      Renderer.create(@getRendererArgs(options.coords))
      .then (win) =>
        Events.start(options)

        if options.updating
          Updater.install(options)

        Tray.display({
          onDrop: ->

          onClick: (e, bounds) =>
            @onClick(bounds, win)

          onRightClick: ->
        })

        return win

    Promise.props({
      ready: ready()
      notify: @notify()
    })
    .get("ready")

  run: (options) ->
    new Promise (resolve, reject) =>
      ## prevent chromium from throttling
      app.commandLine.appendSwitch("disable-renderer-backgrounding")

      app.on "window-all-closed", =>
        @onWindowAllClosed(app)

      app.on "ready", =>
        resolve @ready(options)
}