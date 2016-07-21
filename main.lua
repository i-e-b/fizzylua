local okToJump = false
local acel = {x=0, y=0}
local objects = {}
local ball -- keep a reference for simple control

function love.load()
    world = love.physics.newWorld(0, 200, true)
    --love.physics.setMeter(30) --the height of a meter our world
    --world = love.physics.newWorld(0, 9.81*30, true)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)
-- friction only works on circle shapes if they are non rotating
-- as they will freely rotate otherwise
    ball = NewSimpleThing(circle(20), 400,200, "dynamic", {ball=true})
    ball.b:setMass(20)
    ball.b:setFixedRotation( true ) -- makes friction work on simple circle (forces no rotation)
    ball.f:setRestitution(0.1)    -- make it less bouncy
    ball.f:setFriction(0.4)

    local water = NewSimpleThing(rect(1000,400), 0, 600, "static", {water=true})
    water.f:setSensor(true)

    local floor1 = NewSimpleThing(rect(1000, 10), 400, 400, "static", {floor=true})
    floor1.b:setAngle(-0.4)
    floor1.f:setFriction(0.4)
    local floor2 = NewSimpleThing(rect(1000, 10), -480, 400, "static", {floor=true})
    floor2.b:setAngle(0.4)
    floor2.f:setFriction(0.4)

    local glass = NewSimpleThing(rect(1000, 2), 0, 400, "static", {floor=true, smash=300})
    glass.f:setFriction(0.01)

    text = ""   -- we'll use this to put info text on the screen later
end

function circle(r) return love.physics.newCircleShape(r) end
function rect(w,h) return love.physics.newRectangleShape(w,h) end

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

function love.keypressed(key)
  if key == 'escape' then love.event.quit() end
end

local contactCount = 0
local inWater = 0
function love.update(dt)
    world:update(dt)

    if love.keyboard.isDown("right") then
      ball.b:applyForce(acel.y * -1000, acel.x * 1000)
    elseif love.keyboard.isDown("left") then
      ball.b:applyForce(acel.y * 1000, acel.x * -1000)
    end
    if love.keyboard.isDown("up") and (okToJump or inWater > 0) then
      local jumpForce = 1000
      if (okToJump) then jumpForce = 8000 end
      ball.b:applyForce(acel.x * jumpForce, acel.y * jumpForce)
    elseif love.keyboard.isDown("down") then
      ball.b:applyForce(0, 1000)
    end

    local contacts = world:getContactList()
    for i, cont in ipairs(contacts) do
      if (cont:isTouching()) then
        local a, b = cont:getFixtures()
        local ud_a = a:getUserData();
        local ud_b = b:getUserData();
        local waterBody = nil
        local ballBody = nil

        if (ud_a.water) or (ud_b.water) then
          if (ud_a.ball) then
            waterBody = b:getBody()
            ballBody = a:getBody()
          elseif (ud_b.ball) then
            waterBody = a:getBody()
            ballBody = b:getBody()
          end
          if (ballBody) then
            local bouyForce = math.min(400, math.max(0, ballBody:getY() - (waterBody:getY() - 350)) * 1.75 )
            ballBody:applyForce(0, -bouyForce)
          end
        end
      end
    end

    if string.len(text) > 300 then    -- cleanup when 'text' gets too long
        text = ""
    end

    -- camera follows the ball
    world:translateOrigin(ball.b:getX() - 300, ball.b:getY() - 300)
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
    love.graphics.print(text, 10, 10)
end

function beginContact(a, b, coll)
    x,y = coll:getNormal()
    local ud_a = a:getUserData();
    local ud_b = b:getUserData();
    local contactSpeed = getImpactSpeed(a:getBody(),b:getBody())

    if (ud_a.ball) or (ud_b.ball) then
      if (ud_a.floor) or (ud_b.floor) then
        contactCount = contactCount + 1
        --text = text.."\nContacts: "..contactCount
        acel.x = x
        acel.y = y
        okToJump = true
      elseif (ud_a.water) or (ud_b.water) then
        inWater = inWater + 1
        ball.b:setLinearDamping( 4 )
      end
    end

-- TODO: this should be calculated from the postSolve callback,
-- so we use the force rather than the speed. http://www.iforce2d.net/b2dtut/sticky-projectiles
    if (ud_a.smash) and (contactSpeed > ud_a.smash) then
      a:getBody():destroy()
    elseif (ud_b.smash) and (contactSpeed > ud_b.smash) then
      b:getBody():destroy()
    end

    --text = text.."\n"..a:getUserData().." colliding with "..b:getUserData().." with a vector normal of: "..x..", "..y
    text = text .. "\nSpeed:" .. contactSpeed
end

function getImpactSpeed(a,b)
  local ax, ay = a:getLinearVelocity()
  local bx, by = b:getLinearVelocity()
  local vx = bx - ax
  local vy = by - ay

  return math.sqrt(vx * vx + vy * vy)
end

function endContact(a, b, coll)
    local ud_a = a:getUserData();
    local ud_b = b:getUserData();

    if (ud_a.ball) or (ud_b.ball) then
      if (ud_a.floor) or (ud_b.floor) then
        contactCount = contactCount - 1
      elseif (ud_a.water) or (ud_b.water) then
        inWater = inWater - 1
        if inWater < 1 then
          ball.b:setLinearDamping( 0 )
        end
      end

      --text = text.."\nContacts: "..contactCount
      if contactCount < 1 then
        acel.x = 0
        acel.y = -0.3 -- small amount of 'air' control
        okToJump = false
      end
    end
    --text = text.."\n"..a:getUserData().." uncolliding with "..b:getUserData()
end

-- happens every timer tick for every touching contact
-- except for sensors -- they only get begin/endContact
function preSolve(a, b, coll)
end

-- this one too.
function postSolve(a, b, coll, normalimpulse, tangentimpulse)
  if (math.abs(normalimpulse) > 100) then text = text.."\nimpact force: "..normalimpulse end
end
