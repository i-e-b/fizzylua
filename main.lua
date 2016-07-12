local okToJump = false
local acel = {x=0, y=0}

function love.load()
    world = love.physics.newWorld(0, 200, true)
    world:setCallbacks(beginContact, endContact, preSolve, postSolve)
-- friction works on polyshapes, but not circle shapes unless they are pinned,
-- as they will freely rotate
    ball = {}
        --ball.s = love.physics.newRectangleShape(20, 20)
        ball.s = love.physics.newCircleShape(20)
        ball.b = love.physics.newBody(world, 400,200, "dynamic")
        ball.f = love.physics.newFixture(ball.b, ball.s)
        ball.b:setMass(20)
        ball.b:setFixedRotation( true ) -- makes friction work on simple circle (forces no rotation)
        ball.f:setRestitution(0.1)    -- make it less bouncy
        ball.f:setFriction(0.4)
        ball.f:setUserData("Ball")

    water = {}
        water.b = love.physics.newBody(world, 0,600, "static")
        water.s = love.physics.newRectangleShape(1000,400)
        water.f = love.physics.newFixture(water.b, water.s)
        water.f:setUserData("Water")
        water.f:setSensor(true)

    static = {}
        static.b = love.physics.newBody(world, 400,400, "static")
        static.s = love.physics.newRectangleShape(1000,10)
        static.f = love.physics.newFixture(static.b, static.s)
        static.b:setAngle( -0.4 )
        static.f:setUserData("Block")
        static.f:setFriction(0.4)

    static2 = {}
        static2.b = love.physics.newBody(world, -480,400, "static")
        static2.s = love.physics.newRectangleShape(1000,10)
        static2.f = love.physics.newFixture(static2.b, static2.s)
        static2.b:setAngle( 0.4 )
        static2.f:setUserData("Block")
        static2.f:setFriction(0.4)

    -- todo: add this joint on contact?
    --joint = love.physics.newFrictionJoint( static.b, ball.b, 400, 100, true )
    --joint:setMaxForce( 800 )
    --joint:setMaxTorque( 100 )

    text       = ""   -- we'll use this to put info text on the screen later
    persisting = 0    -- we'll use this to store the state of repeated callback calls
end

function love.keypressed(key)
  if key == 'escape' then love.event.quit() end
end

local contactCount = 0
local inWater = 0
function love.update(dt)
    world:update(dt)

    if inWater > 0 then
      local bouyForce = math.min(400, math.max(0, ball.b:getY() - (water.b:getY() - 350)) * 1.75 )
      ball.b:applyForce(0, -bouyForce)
    end

    if love.keyboard.isDown("right") then
      ball.b:applyForce(acel.y * -1000, acel.x * 1000)
    elseif love.keyboard.isDown("left") then
      ball.b:applyForce(acel.y * 1000, acel.x * -1000)
    end
    if love.keyboard.isDown("up") and okToJump then
        ball.b:applyForce(acel.x * 8000, acel.y * 8000)
        --ball.b:applyForce(0, -8000)
        okToJump = false
    elseif love.keyboard.isDown("down") then
        ball.b:applyForce(0, 1000)
    end

    if string.len(text) > 768 then    -- cleanup when 'text' gets too long
        text = ""
    end

    -- camera follows the ball
    world:translateOrigin(ball.b:getX() - 300, ball.b:getY() - 300)
end

function love.draw()
    love.graphics.setColor(0, 0, 255, 255)
    love.graphics.polygon("line", water.b:getWorldPoints(water.s:getPoints()))

    love.graphics.setColor(255, 255, 255, 255)
    love.graphics.circle("line", ball.b:getX(),ball.b:getY(), ball.s:getRadius(), 20)
    --love.graphics.polygon("line", ball.b:getWorldPoints(ball.s:getPoints()))
    love.graphics.polygon("line", static.b:getWorldPoints(static.s:getPoints()))
    love.graphics.polygon("line", static2.b:getWorldPoints(static2.s:getPoints()))

    love.graphics.print(text, 10, 10)
end

function beginContact(a, b, coll)
    x,y = coll:getNormal()
    local ud_a = a:getUserData();
    local ud_b = b:getUserData();

    if (ud_a == "Ball") or (ud_b == "Ball") then
      if (ud_a == "Block") or (ud_b == "Block") then
        contactCount = contactCount + 1
        text = text.."\nContacts: "..contactCount
        acel.x = x
        acel.y = y
        okToJump = true
      elseif (ud_a == "Water") or (ud_b == "Water") then
        inWater = inWater + 1
        ball.b:setLinearDamping( 4 )
      end
    end

    text = text.."\n"..a:getUserData().." colliding with "..b:getUserData().." with a vector normal of: "..x..", "..y
end

function endContact(a, b, coll)
    persisting = 0

    local ud_a = a:getUserData();
    local ud_b = b:getUserData();

    if (ud_a == "Ball") or (ud_b == "Ball") then
      if (ud_a == "Block") or (ud_b == "Block") then
        contactCount = contactCount - 1
      elseif (ud_a == "Water") or (ud_b == "Water") then
        inWater = inWater - 1
        if inWater < 1 then
          ball.b:setLinearDamping( 0 )
        end
      end

      text = text.."\nContacts: "..contactCount
      if contactCount < 1 then
        acel.x = 0
        acel.y = -0.3 -- small amount of 'air' control
        okToJump = false
      end
    end
    text = text.."\n"..a:getUserData().." uncolliding with "..b:getUserData()
end

function preSolve(a, b, coll)
    if persisting == 0 then    -- only say when they first start touching
        text = text.."\n"..a:getUserData().." touching "..b:getUserData()
    elseif persisting < 20 then    -- then just start counting
        text = text.." "..persisting
    end
    persisting = persisting + 1    -- keep track of how many updates they've been touching for
end

function postSolve(a, b, coll, normalimpulse, tangentimpulse)
end
