local okToJump = false
local acel = {x=0, y=0}
local objects = {}
local ball -- keep a reference for simple control
local GX = 300
local GY = 300

local inWater = false
local onFloor = false

function love.load()
  --world = love.physics.newWorld(0, 200, true)
  world = love.physics.newWorld(0, 9.81*20, true)
  love.physics.setMeter(20) --how many pixels equal a metre.
  world:setCallbacks(beginContact, endContact, preSolve, postSolve)
  -- friction only works on circle shapes if they are non rotating
  -- as they will freely rotate otherwise
  ball = NewSimpleThing(circle(14), 400,200, "dynamic", {ball=true, passing=nil})
  ball.b:setFixedRotation( true ) -- makes friction work on simple circle (forces no rotation)
  ball.f:setRestitution(0.1)    -- make it less bouncy
  ball.f:setFriction(0.6)
  ball.b:setMass(20)

  local water = NewSimpleThing(rect(1000,400), 0, 600, "static", {water=true})
  water.f:setSensor(true)

  local floor1 = NewSimpleThing(rect(400, 10), 200, 480, "static", {floor=true})
  floor1.b:setAngle(-0.4)
  floor1.f:setFriction(0.4)
  local floor2 = NewSimpleThing(rect(800, 10), -480, 400, "static", {floor=true})
  floor2.b:setAngle(0.4)
  floor2.f:setFriction(0.4)
  local floor3 = NewSimpleThing(rect(1400, 10), 1000, 400, "static", {floor=true})
  floor3.f:setFriction(0.8)

  local wall = NewSimpleThing(rect(10, 1000), 1400, 400, "static", {})

  local glass = NewSimpleThing(rect(1000, 2), 0, 400, "static", {floor=true, smash=6400})
  glass.f:setFriction(0.01)
  -- A few vertical things to break
  NewSimpleThing(rect(3, 100), 800, 350, "static", {smash=5000})
  NewSimpleThing(rect(3, 100), 850, 350, "static", {smash=5000})
  NewSimpleThing(rect(3, 100), 900, 350, "static", {smash=5000})

  NewSimpleThing(rect(50, 10), 1300, 340, "static", {floor=true, oneway=true})
  NewSimpleThing(rect(50, 10), 1200, 300, "static", {floor=true})
  NewSimpleThing(rect(50, 10), 1100, 240, "static", {floor=true})
end

function circle(r) return love.physics.newCircleShape(r) end
function rect(w,h) return love.physics.newRectangleShape(w,h) end

-- Create a new body, shape and connected fixture.
-- These are added to the world, the object list and returned
function NewSimpleThing (shape, x, y, type, userData)
  local thing = {}
  thing.b = love.physics.newBody(world, x, y, type)
  thing.s = shape
  thing.f = love.physics.newFixture(thing.b, thing.s)
  thing.data = userData
  thing.f:setUserData(userData)
  table.insert(objects, thing);
  return thing
end

-- exit on ESC for testing
function love.keypressed(key)
  if key == 'escape' then love.event.quit() end
end

-- trigger the physics engine and process any general collision processing
function processPhysics(dt)
  inWater = false
  onFloor = false

  local waterDepth = 0
  local fx = 0
  local fy = 0 -- floor normal

  ball.b:setLinearDamping(0)
  local contacts = world:getContactList()
  for i, cont in ipairs(contacts) do
    if (cont:isTouching()) then
      local a, b = cont:getFixtures()
      local ud_a = a:getUserData();
      local ud_b = b:getUserData();
      local waterBody = nil
      local waterFix = nil
      local ballBody = nil
      local floorFix = nil

      if (ud_a.ball) then ballBody = a:getBody()
      elseif (ud_a.water) then waterFix = a; waterBody = a:getBody()
      elseif (ud_a.floor) then floorFix = a
      end

      if (ud_b.ball) then ballBody = b:getBody()
      elseif (ud_b.water) then waterFix = b; waterBody = b:getBody()
      elseif (ud_b.floor) then floorFix = b
      end

      if (ballBody) then
        if (waterBody) then
          -- keep the deepest water, so we can have overlap regions
          local r = getRadius(waterFix)
          waterDepth = math.max(waterDepth, ballBody:getY() - (waterBody:getY() - r))
          inWater = true
        elseif (floorFix) and (ball.data.passing ~= floorFix) then
          onFloor = true
          --onFloor = true
          local x,y = cont:getNormal()
          -- add the normal, and we will scale it at the end
          fx = fx + x
          fy = fy + y
        end
      end
    end
  end

  if inWater then
    local bouyForce = math.min(1000, waterDepth + 140 )
    local hh = getRadius(ball.f) * 0.5
    if (waterDepth > hh) then
      ball.b:applyForce(0, -bouyForce * ball.b:getMass())
    end
    ball.b:setLinearDamping( 4 )
    acel.x = 0
    acel.y = -0.5 -- swimming is half power
    okToJump = false
  elseif onFloor then
    fx,fy = Normalise(fx,fy)
    acel.x = math.max(-0.4, math.min(fx, 0.4))
    acel.y = math.max(-1, math.min(fy, 0))
    okToJump = true
  else
    acel.x = 0
    acel.y = -0.3 -- small amount of 'air' control
    okToJump = false
  end

  world:update(dt)
end

function love.update(dt)
  processPhysics(dt)

  local v = 140
  if love.keyboard.isDown("right") then
    ball.b:applyLinearImpulse(acel.y * -v, acel.x * v)
  elseif love.keyboard.isDown("left") then
    ball.b:applyLinearImpulse(acel.y * v, acel.x * -v)
  end
  if love.keyboard.isDown("up") and (okToJump or inWater) then
    local jumpForce = v
    if (okToJump) then jumpForce = v * 7 end
    ball.b:applyLinearImpulse(acel.x * jumpForce, acel.y * jumpForce)
  elseif love.keyboard.isDown("down") then
    ball.b:applyLinearImpulse(0, v)
  end

  -- camera follows the ball
  local dx = math.floor(ball.b:getX() - 300)
  local dy = math.floor(ball.b:getY() - 300)
  world:translateOrigin(dx, dy)
  GX = GX + dx
  GY = GY + dy
end

function love.draw()
  for i, obj in ipairs(objects) do
    if (not obj.b:isDestroyed()) then
      -- set color based on type
      if (obj.data.floor) then
        love.graphics.setColor(200, 255, 200, 255)
      elseif (obj.data.water) then
        love.graphics.setColor(0, 0, 255, 100)
      else
        love.graphics.setColor(255, 255, 255, 255)
      end

      -- draw the shape
      if (obj.data.ball) then
        love.graphics.circle("fill", obj.b:getX(), obj.b:getY(), obj.s:getRadius(), 20)
      else
        love.graphics.polygon("fill", obj.b:getWorldPoints(obj.s:getPoints()))
      end
    end
  end

  love.graphics.setColor(255, 255, 0, 255)
  local msg = GX..","..GY
  if onFloor then msg = msg..", floor" end
  if inWater then msg = msg..", water" end
  love.graphics.print(msg, 10, 10)
end

function beginContact(a, b, coll)
  local x,y = coll:getNormal()
  local ud_a = a:getUserData()
  local ud_b = b:getUserData()

  if (ud_a.ball) or (ud_b.ball) then
    if (ud_a.floor) or (ud_b.floor) then
      local floor = a; if (ud_b.floor) then floor = b end

      if (floor:getUserData().oneway
        ) and (y > 0.4) then -- mostly up (refine later)
        coll:setEnabled(false)
        ball.data.passing = floor
      end
    end
  end
end

function Normalise (x,y)
  local scale = math.sqrt(x*x + y*y)
  return x*scale, y*scale
end

function getImpactSpeed(a,b)
  local ax, ay = a:getLinearVelocity()
  local bx, by = b:getLinearVelocity()
  local vx = bx - ax
  local vy = by - ay

  return math.sqrt(vx * vx + vy * vy)
end

function getHeight(fixture)
  local topLeftX, topLeftY, bottomRightX, bottomRightY = fixture:getBoundingBox()
  return bottomRightY - topLeftY -- kinda rough!
end
function getRadius(fixture)
  local topLeftX, topLeftY, bottomRightX, bottomRightY = fixture:getBoundingBox()
  return (bottomRightY - topLeftY) * 0.5 -- incredibly rough!
end

function endContact(a, b, coll)
  if a == ball.data.passing then
    ball.data.passing = nil
  elseif b == ball.data.passing then
    ball.data.passing = nil
  end
end

-- happens every timer tick for every touching contact
-- except for sensors -- they only get begin/endContact
-- here you can choose to 'cancel' the contact (for pass through)
function preSolve(a, b, coll)
  -- if the ball is passing through another object,
  -- and this is the contact with that object, we
  -- cancel the contact
  local ud_a = a:getUserData()
  local ud_b = b:getUserData()

  if (ud_a.ball) or (ud_b.ball) then
    if (ball.data.passing == a) or (ball.data.passing == b) then
      coll:setEnabled(false)
    end
  end
end

-- happens every timer tick for every touching contact
-- except for sensors -- they only get begin/endContact
-- you can't cancel anymore, but you know the force of impact
function postSolve(a, b, coll, normalimpulse, tangentimpulse)
  -- Handle smashes. We re-apply some of the normal impulse
  -- to the impacting object, otherwise you get an odd-looking pause.
  local ud_a = a:getUserData()
  local ud_b = b:getUserData()
  nx, ny = coll:getNormal()
  local continueForce = normalimpulse * 0.4
  if (ud_a.smash) and (normalimpulse > ud_a.smash) then
    a:getBody():destroy()
    b:getBody():applyLinearImpulse(-nx*continueForce,-ny*continueForce) -- allow pass through
  elseif (ud_b.smash) and (normalimpulse > ud_b.smash) then
    b:getBody():destroy()
    a:getBody():applyLinearImpulse(-nx*continueForce,-ny*continueForce) -- allow pass through
  end
end
