local textsize = 0.02

function ARInit()
  ar.setdata("result", nil)
  ar.setdata("input", nil)
  ar.setdata("op", nil)
  ar.setdata("lastop", nil)
  ar.setdata("lastinput", nil)
end

function ARRenderScene()
  local data = ar.getdata()
  local tapped = ar.gettapped()

  if tapped then
    ar.cleartap()
    if tonumber(tapped) ~= nil then
      DoNumber(tonumber(tapped))
    elseif tapped == "." then
      local input = data.input
      if not input:find(".", 1, true) then
        input = input .. tapped
        ar.setdata("input", input)
      end
    elseif tapped == "+" then
      DoOp("+")
    elseif tapped == "-" then
      DoOp("-")
    elseif tapped == "*" then
      DoOp("*")
    elseif tapped == "/" then
      DoOp("/")
    elseif tapped == "=" then
      DoEquals()
    elseif tapped == "AC" then
      AllClear()
    end
  end

  data = ar.getdata()
  if tapped then
    print(data.result, data.op, data.input)
  end

  local rows = {
    { Btn("AC", "lightGray"), Btn("+/-", "lightGray"), Btn("%", "lightGray"), Btn("/", "orange") },
    { Btn("7", "white"), Btn("8", "white"), Btn("9", "white"), Btn("*", "orange") },
    { Btn("4", "white"), Btn("5", "white"), Btn("6", "white"), Btn("-", "orange") },
    { Btn("1", "white"), Btn("2", "white"), Btn("3", "white"), Btn("+", "orange") },
    { Btn2("0", "white"), {}, Btn(".", "white"), Btn("=", "orange") },
  }
  for r, row in ipairs(rows) do
    for c, btn in ipairs(row) do
      btn.pos = { (c-1) * 0.04, (r-1) * -0.03, 0 }
    end
  end

  local display = tostring(data.result or 0)
  if data.input ~= nil then
    display = tostring(data.input)
  end

  return {
    pos = { 0.06, 0, 0 },

    { type = "text", text = display, textsize = textsize, pos = { 0, 0.03, 0 } },
    rows,
  }
end

function Btn(text, color)
  return {
    { type = "box", color = color, pos = { 0, 0, 0.005 }, size = { 0.04, 0.03, 0.01 } },
    { type = "text", text = text, textsize = textsize, textalign = "center", pos = { 0, 0, 0.01 } },
    { type = "triggerbox", id = text, pos = { 0, 0, 0.01 }, size = { 0.04, 0.03, 0.02 } }
  }
end

function Btn2(text, color)
  return {
    { type = "box", color = color, pos = { 0.02, 0, 0.005 }, size = { 0.08, 0.03, 0.01 } },
    { type = "text", text = text, textsize = textsize, textalign = "center", pos = { 0.02, 0, 0.01 } },
    { type = "triggerbox", id = text, pos = { 0.02, 0, 0.01 }, size = { 0.08, 0.03, 0.02 } },
  }
end

function DoNumber(num)
  local data = ar.getdata()
  local input = data.input or ""
  input = input .. num
  ar.setdata("input", input)
end

function DoOp(op)
  local data = ar.getdata()
  if data.result == nil then
    -- No result yet at all. Apply input if any, and set op.
    ar.setdata("result", data.input or 0)
    ar.setdata("input", nil)
    ar.setdata("op", op)
  elseif data.input == nil then
    -- Prior result, but no input, e.g. "123 +". Set op.
    ar.setdata("op", op)
  else
    -- Prior result and new input implies we have an op.
    -- Apply it (equals sign) and then set the new op.
    assert(data.op)
    DoEquals()
    ar.setdata("op", op)
  end
end

function DoEquals()
  local data = ar.getdata()
  local op = data.op
  local result = data.result
  local input = data.input

  if input == nil then
    -- repeat the last op / input, if any
    op = data.lastop
    input = data.lastinput
  end

  if op == "+" then
    result = result + input
  elseif op == "-" then
    result = result - input
  elseif op == "*" then
    result = result * input
  elseif op == "/" then
    result = result / input
  else
    print("WARNING! Unknown op "..op)
  end
  ar.setdata("result", result)
  ar.setdata("input", nil)
  ar.setdata("op", nil)
  ar.setdata("lastop", op)
  ar.setdata("lastinput", input)
end

function AllClear()
  ar.setdata("result", nil)
  ar.setdata("input", nil)
  ar.setdata("op", nil)
  ar.setdata("lastop", nil)
  ar.setdata("lastinput", nil)
end