-- local ar = require("ar")

function ARInit()
  ar.setdata("board", {
    "", "", "",
    "", "", "",
    "", "", "",
  })
  ar.setdata("turn", "x")
end

function ARRenderScene()
  local data = ar.getdata()
  local tapped = ar.gettapped()

  if tapped then
    ar.cleartap()
    local idx = tonumber(tapped:sub(-1))
    if data.board[idx] == "" then
      print("filling cell", idx, "with", data.turn)
      ar.setdata("board", idx, data.turn)
      if data.turn == "x" then
        ar.setdata("turn", "o")
      else
        ar.setdata("turn", "x")
      end
    end
    pprint("board is now", ar.getdata().board)
  end

  data = ar.getdata()
  -- pprint(data)
  -- pprint(data.board)

  -- Check for winner
  local tracks = {
    {1, 2, 3},
    {4, 5, 6},
    {7, 8, 9},
    {1, 4, 7},
    {2, 5, 8},
    {3, 6, 9},
    {1, 5, 9},
    {7, 5, 3},
  }
  local winner = nil
  for _, track in ipairs(tracks) do
    local c1 = data.board[track[1]]
    local c2 = data.board[track[2]]
    local c3 = data.board[track[3]]
    if c1 == "x" and c2 == "x" and c3 == "x" then
      winner = "x"
      break
    elseif c1 == "o" and c2 == "o" and c3 == "o" then
      winner = "o"
      break
    end
  end

  -- Check for draw
  local draw = true
  for i = 1, 9 do
    if data.board[i] == "" then
      draw = false
    end
  end

  local msg = "???"
  if draw then
    msg = "It's a draw!"
  elseif winner then
    msg = winner.." wins!"
  elseif data.turn == "x" then
    msg = "x's turn"
  elseif data.turn == "o" then
    msg = "o's turn"
  end

  local cells = {}
  for i, y in ipairs({ 1, 0, -1 }) do
    for j, x in ipairs({ -1, 0, 1 }) do
      local idx = (i-1) * 3 + j
      table.insert(cells, { type = "triggerbox", id = "cell"..idx, pos = { x * 0.05, y * 0.05, 0 }, size = { 0.05, 0.05, 0.01 } })
      local contents = data.board[idx]
      if contents ~= "" then
        table.insert(cells, {
          type = "text",
          pos = { x * 0.06, y * 0.06, 0 },
          text = contents, textalign = "center",
        })
      end
    end
  end

  return {
    { pos = { 0, 0.20, 0 },
      { type = "box", pos = { -0.03, 0, 0 }, size = { 0.01, 0.17, 0.01 } },
      { type = "box", pos = { 0.03, 0, 0 }, size = { 0.01, 0.17, 0.01 } },
      { type = "box", pos = { 0, -0.03, 0 }, size = { 0.17, 0.01, 0.01 } },
      { type = "box", pos = { 0, 0.03, 0 }, size = { 0.17, 0.01, 0.01 } },
      cells,
      { type = "text", text = msg, pos = { -0.08, -0.15, 0 } }
    }
  }
end
