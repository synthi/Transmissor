engine.name = 'PolyPerc'

function init()
  print("TEST INIT")
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(0, 32)
  screen.text("ALIVE " .. os.clock())
  screen.update()
end
