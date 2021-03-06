local okToJump = false
local acel = {x=0, y=0}
local objects = {}
local GX = 300 -- global X offset, to handle camera tracking
local GY = 300 -- and global Y
local ball -- keep a reference for simple control
local swapper -- something to swap places with
local mousePoint -- physics object that represents the mouse pointer

local painFade = 0

local inWater = false
local onFloor = false
local canSwap = false

function love.load()
  --world = love.physics.newWorld(0, 200, true)
  world = love.physics.newWorld(0, 9.81*20, true)
  love.physics.setMeter(20) --how many pixels equal a metre.
  world:setCallbacks(beginContact, endContact, preSolve, postSolve)
  -- friction only works on circle shapes if they are non rotating
  -- as they will freely rotate otherwise. This can be done by preventing rotation,
  -- setting angular damping, or supplying a counter-rotating torque. We do the second two.
  ball = NewSimpleThing(circle(14), 400,200, "dynamic", {ball=true, passing=nil, isPlayer=true})
  ball.b:setAngularDamping(1)
  ball.f:setRestitution(0.1)    -- make it less bouncy
  ball.f:setFriction(20)
  ball.b:setMass(20)

  -- press space to swap with this thing. Both position and momentum are swapped
  swapper = NewSimpleThing(rect(20, 30), 480,200, "dynamic", {floor=true})
  swapper.b:setMass(70) -- different swap masses have different effects

  -- Water is done as a sensor, and we apply a bouyant force separately
  -- when the player ball is in contact with water.
  local water = NewSimpleThing(rect(1000,400), 0, 600, "static", {water=true})
  water.f:setSensor(true)

  -- a sensor blob that is repeatedly set to the mouse position. Simplest way to do mouse interaction
  mousePoint = NewSimpleThing(rect(4,4), 0,0, "static", {isMouse=true})
  mousePoint.f:setSensor(true)
  mousePoint.b:setFixedRotation(true)

  -- A bunch of floor sections
  local floor1 = NewSimpleThing(rect(400, 10), 200, 480, "static", {floor=true})
  floor1.b:setAngle(-0.4)
  floor1.f:setFriction(0.4)
  local floor2 = NewSimpleThing(rect(800, 10), -480, 400, "static", {floor=true})
  floor2.b:setAngle(0.4)
  floor2.f:setFriction(0.4)
  local floor3 = NewSimpleThing(rect(1400, 10), 1000, 400, "static", {floor=true})
  floor3.f:setFriction(0.8)
  NewSimpleThing(rect(10, 300), -840, 100, "static", {})
  NewSimpleThing(rect(10, 1000), 1400, 400, "static", {})

  local glass = NewSimpleThing(rect(1000, 2), 0, 400, "static", {floor=true, smash=6400})
  glass.f:setFriction(0.01)

  -- A few vertical things to break
  NewSimpleThing(rect(3, 100), 800, 350, "dynamic", {smash=170})
  NewSimpleThing(rect(3, 100), 850, 350, "dynamic", {smash=170})
  NewSimpleThing(rect(7, 100), 900, 350, "dynamic", {smash=1070})
  NewSimpleThing(rect(10, 10), 940, 380, "static", {floor=true})

  NewSimpleThing(rect(50, 10), 1300, 340, "static", {floor=true, oneway=true})

  -- some hanging floor sections
  local pin1 = NewSimpleThing(circle(2), 1100,200, "static", {ball=true})
  pin1.f:setSensor(true)
  local float1 = NewSimpleThing(rect(50, 10), 1100, 240, "dynamic", {floor=true, swing=true})
  float1.b:setLinearDamping(1)
  float1.b:setMass(20)
  love.physics.newRopeJoint( pin1.b, float1.b, 1100,200,  1075, 240,  70, false )
  love.physics.newRopeJoint( pin1.b, float1.b, 1100,200,  1125, 240,  70, false )

  local pin2 = NewSimpleThing(circle(2), 1200,240, "static", {ball=true})
  pin2.f:setSensor(true)
  local float2 = NewSimpleThing(rect(50, 10), 1200, 300, "dynamic", {floor=true, swing=true})
  float2.b:setLinearDamping(1)
  float2.b:setMass(20)
  love.physics.newDistanceJoint( pin2.b, float2.b, 1200,240,  1175, 300,  false )
  love.physics.newDistanceJoint( pin2.b, float2.b, 1200,240,  1225, 300,  false )
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
      local floorIsSwing = false

      if (ud_a.ball) then ballBody = a:getBody()
      elseif (ud_a.water) then waterFix = a; waterBody = a:getBody()
      elseif (ud_a.floor) then
        floorFix = a
        floorIsSwing = ud_a.swing
      end

      if (ud_b.ball) then ballBody = b:getBody()
      elseif (ud_b.water) then waterFix = b; waterBody = b:getBody()
      elseif (ud_b.floor) then
        floorFix = b
        floorIsSwing = ud_b.swing
      end

      if (ballBody) then
        if (waterBody) then
          -- keep the deepest water, so we can have overlap regions
          local r = getRadius(waterFix)
          waterDepth = math.max(waterDepth, ballBody:getY() - (waterBody:getY() - r))
          inWater = true
        elseif (floorFix) and (ball.data.passing ~= floorFix) then
          onFloor = true
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
    if onFloor then
      acel.y = -2 -- extra power to kick off or climb out
    else
      acel.y = -0.5 -- swimming is half power
    end
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
  updateMousePointer()
  processPhysics(dt)
  painFade = math.max(0, painFade - dt)

  local v = 140
  if love.keyboard.isDown("right") then
    if onFloor and (not inWater) then
      ball.b:applyAngularImpulse(1000)
    else
      ball.b:applyLinearImpulse(acel.y * -v, acel.x * v)
    end
  elseif love.keyboard.isDown("left") then
    if onFloor and (not inWater) then
      ball.b:applyAngularImpulse(-1000)
    else
      ball.b:applyLinearImpulse(acel.y * v, acel.x * -v)
    end
  else
    -- counter torque to slow down
    local counterTorque = -300 * ball.b:getAngularVelocity()
    ball.b:applyAngularImpulse(SaturateRange(counterTorque, 1000))
  end
  if love.keyboard.isDown("up") and (okToJump or inWater) then
    local jumpForce = v
    if (okToJump) then jumpForce = v * 7 end
    ball.b:applyLinearImpulse(acel.x * jumpForce, acel.y * jumpForce)
  elseif love.keyboard.isDown("down") then
    ball.b:applyLinearImpulse(0, v)
  end

  if love.keyboard.isDown("space") then -- swap ball and 'swapper'
    if (canSwap) then
      canSwap = false
      swapBodies(ball.b, swapper.b)
    end
  else
    canSwap = true
  end

  -- camera follows the ball
  local dx = math.floor(ball.b:getX() - 300)
  local dy = math.floor(ball.b:getY() - 300)
  world:translateOrigin(dx, dy)
  GX = GX + dx
  GY = GY + dy
end

function love.draw()
  love.graphics.setBackgroundColor(255 * painFade, 0, 0, 255)

  -- draw joints (just dumb lines at the moment)
  love.graphics.setColor(255, 255, 255, 127)
  local joints = world:getJointList()
  for i, jnt in ipairs(joints) do
    if (not jnt:isDestroyed()) then
      local x1, y1, x2, y2 = jnt:getAnchors()
      love.graphics.line(x1, y1, x2, y2)
    end
  end

  -- draw the objects
  for i, obj in ipairs(objects) do
    if (not obj.b:isDestroyed()) then
      -- set color based on type
      if (obj.data.hilight) then
        love.graphics.setColor(0, 255, 255, 255)
      elseif (obj.data.floor) then
        love.graphics.setColor(200, 255, 200, 255)
      elseif (obj.data.water) then
        love.graphics.setColor(0, 0, 255, 100)
      else
        love.graphics.setColor(255, 255, 255, 255)
      end

      -- draw the shape
      if (obj.data.ball) then
        love.graphics.circle("fill", obj.b:getX(), obj.b:getY(), obj.s:getRadius() - 2, 20)
        local a = obj.b:getAngle()
        love.graphics.arc("fill", obj.b:getX(), obj.b:getY(), obj.s:getRadius(), a, a + 1, 4)
      else
        love.graphics.polygon("fill", obj.b:getWorldPoints(obj.s:getPoints()))
      end
    end
  end

  love.graphics.setColor(255, 255, 0, 255)
  local msg = GX..", "..GY..", "..(math.floor(ball.b:getAngularVelocity() + 0.5))
  if onFloor then msg = msg..", floor" end
  if inWater then msg = msg..", water" end
  love.graphics.print(msg, 10, 10)
end

function SaturateRange(v,r)
  return math.min(r, math.max(-r, v))
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

-- swap the position and momentum of two bodies
function swapBodies(a,b)
  local x1, y1 = a:getPosition()
  local x2, y2 = b:getPosition()

  local xm1, ym1 = getMomentum(a)
  local xm2, ym2 = getMomentum(b)

  a:setPosition(x2,y2)
  b:setPosition(x1,y1)

  a:setLinearVelocity(0,0)
  b:setLinearVelocity(0,0)
  a:applyLinearImpulse( xm2, ym2 )
  b:applyLinearImpulse( xm1, ym1 )

  a:setAwake(true)
  b:setAwake(true)
end

function getMomentum(body)
  local x, y = body:getLinearVelocity()
  local mass = body:getMass()

  return x*mass,y*mass
end

function updateMousePointer()
  -- this is a bit complex, as we need to wake up nearby bodies
  -- to make beginContact and endContact work properly
  mousePoint.b:setPosition(love.mouse.getPosition())
  local topLeftX, topLeftY, bottomRightX, bottomRightY = mousePoint.f:getBoundingBox(1)
  world:queryBoundingBox(topLeftX, topLeftY, bottomRightX, bottomRightY,
    function(fixture)
      if (not fixture:isDestroyed()) then
        fixture:getBody():setAwake(true)
      end
      return true -- always continue
    end
  )
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

  if (ud_a.isMouse) then ud_b.hilight = true end
  if (ud_b.isMouse) then ud_a.hilight = true end
end

function endContact(a, b, coll)
  local ud_a = a:getUserData()
  local ud_b = b:getUserData()

  if a == ball.data.passing then
    ball.data.passing = nil
  elseif b == ball.data.passing then
    ball.data.passing = nil
  end

  if (ud_a.isMouse) then ud_b.hilight = false end
  if (ud_b.isMouse) then ud_a.hilight = false end
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

  if (ud_a.isPlayer or ud_b.isPlayer) and (normalimpulse > 6000) then painFade = 1 end

  local continueForce = normalimpulse * 0.4
  if (ud_a.smash) and (normalimpulse > ud_a.smash) then
    a:getBody():destroy()
    b:getBody():applyLinearImpulse(-nx*continueForce,-ny*continueForce) -- allow pass through
  elseif (ud_b.smash) and (normalimpulse > ud_b.smash) then
    b:getBody():destroy()
    a:getBody():applyLinearImpulse(-nx*continueForce,-ny*continueForce) -- allow pass through
  end
end
