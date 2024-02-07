require "love.timer"

local gid,un,pw = ...

local luapb = require("sdk.luapb.luapb")
local socket = require("socket")
local base64 = require("sdk.base64")
local rc4 = require("sdk.rc4")
local json = require("sdk.json")
local https = require("https")
opts = {data=json.encode({GameID=tonumber(gid), Username=un, Password=pw})}
code, body, _ = https.request("https://api.planetaryprocessing.io//_api/golang.planetaryprocessing.io/apis/httputils/HTTPUtils/GetKey", opts)
if code ~= 200 then
  print("failed to authenticate")
  return
end
key = json.decode(body)
key = base64.decode(key.Key)
local rc4in = rc4(key)
local rc4out = rc4(key)

local out = love.thread.getChannel("out")
local inp = love.thread.getChannel("in")

local loginproto = {
  [1]={type="string", name="Token"},
  [2]={type="uint64", name="GameID"},
  [3]={type="string", name="UUID"},
  [4]={type="string", name="Email"},
  [5]={type="string", name="Password"}
}

local packetproto = {
  [1]={type="proto", name="Move", proto={
    [1]={type="double", name="X"},
    [2]={type="double", name="Y"},
    [3]={type="double", name="Z"}
  }},
  [2]={type="proto", name="Update", proto={
    [1]={type="string", name="EntityID"},
    [2]={type="double", name="X"},
    [3]={type="double", name="Y"},
    [4]={type="double", name="Z"},
    [5]={type="bytes", name="Data"},
    [6]={type="string", name="Type"}
  }},
  [3]={type="proto", name="Delete", proto={
    [1]={type="string", name="EntityID"}
  }},
  [4]={type="bool", name="Leave"},
  [5]={type="string", name="Arbitrary"},
  [6]={type="string", name="Event"}
}

s = socket.tcp()
i, _ = s:connect("localhost", 4101)
if i ~= 1 then
  print("failed connection")
  return
end

_,err,_ = s:send(base64.encode(luapb.serialise({Email=un, Password=pw, GameID=tonumber(gid)}, loginproto)).."\n")
if err then
  print(err)
  return
end

res,err,_ = s:receive("*l")
if err then
  out:push("")
  print(err)
  return
end

out:push(luapb.deserialise(base64.decode(res), loginproto))

_,err,_ = s:send(base64.encode(rc4out(luapb.serialise({Move={X=0, Y=0}}, packetproto))).."\n")
if err then
  out:push("")
  print(err)
  return
end

s:settimeout(0.05)

local tmp = ""

while true do
  res,err,_ = s:receive("*l")
  if err then
    if err ~= "timeout" then
      print(err)
      return
    end
  else
    ok, bts = pcall(base64.decode, res)
    if ok then
      bts = rc4in(bts)
      ok, msg = pcall(luapb.deserialise, bts, packetproto)
      if ok then
        out:push(msg)
      end
    end
  end
  msg = inp:pop()
  if msg then
    local d = base64.encode(rc4out(luapb.serialise(msg, packetproto)))
    print(d)
    s:send(d.."\n")
  end
end
