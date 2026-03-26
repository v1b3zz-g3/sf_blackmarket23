function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
end

function loadModel(model)
    if HasModelLoaded(model) then return end
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end
end

function loadPtfx(dict)
    if HasNamedPtfxAssetLoaded(dict) then return end
    RequestNamedPtfxAsset(dict)
    while not HasNamedPtfxAssetLoaded(dict) do Wait(10) end
end

function loadAudio(audioBank)
    if RequestScriptAudioBank(audioBank, false, -1) then return end
    while not RequestScriptAudioBank(audioBank, false, -1) do Wait(10) end
end

function printError(text)
    print("^1[sf_blackmarket] Script Error: " .. text .. "^7")
end

function GetObjectOffsetFromCoords(coords, x, y, z)
    local heading = math.rad(coords.w)
    local nx = coords.x + x * math.cos(heading) - y * math.sin(heading)
    local ny = coords.y + x * math.sin(heading) + y * math.cos(heading)
    local nz = coords.z + z
    return vector3(nx, ny, nz)
end
