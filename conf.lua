function love.conf(t)
  t.version = "0.10.1"  -- The LÖVE version this game was built with

  -- Same resolution as my phone. Independence later!
  t.window.width = 800
  t.window.height = 600

  t.accelerometerjoystick = false

  t.window.title = "physics"
  t.window.borderless = false
  t.window.fullscreen = false
  --t.console = true
end
