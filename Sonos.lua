-- #region Start --
json = require('json')
debug = false
URI = "https://www.symetrix.co/sonos/ "
Host_Path = "https://api.sonos.com"
Control_Host_Path = "https://api.ws.sonos.com"
Authorization_Code = ""
Household_ID = nil
Group_ID = nil
Scroll_Lock = false
Count = 0
Vol_Count = 0
Volume_State = 0
Play_State = nil
Sonos_Mute_State = ""
--Sonos_Table = {1, 5, 10, 20, 25} --Save for later use. 
Token_Refresh_Times = {"00:00", "06:00", "12:00", "18:00"} 
Update_Time = 1
Playlists = {}

Access_Token = NamedControl.GetText("Access")
Refresh_Token = NamedControl.GetText("Refresh_Token")

NamedControl.SetPosition("Connected", 0)
NamedControl.SetPosition("Mute", 0)
NamedControl.SetText("Playlists", "")
NamedControl.SetValue("Playlist Select", 0)
NamedControl.SetText("Current_URL", "")
NamedControl.SetText("Track", "")
NamedControl.SetText("Artist", "")
NamedControl.SetText("Album", "")

-- Remove trailing 0 and decimal for Sonos.
function format(str)

   Formatted_Str = string.gsub(str,".0", "")
   return Formatted_Str
end

-- Retruns the length of the Playlist table in order to limit how much you can increase the playlist button. 
function tablelength(T)

   local count = 0
   for _ in pairs(T) do count = count + 1 end
   return count
end
-- #endregion Start --

-- #region Responses. --

-- Gets Auth token. 
function Authorization_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then 
      print(Data)
   end

   decodedJSON = json.decode(Data)
   Access_Token = decodedJSON.access_token
   Refresh_Token = decodedJSON.refresh_token

   NamedControl.SetText("Access", Access_Token)
   NamedControl.SetText("Refresh_Token", Refresh_Token)
   NamedControl.SetText("ClientID", "")
end

-- Gets Household ID, You can have multiple Household ID's it is needed to control different 'zones' in a house.
-- This module expects the use of 1 Household ID.
function Household_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then 
      print(Data)
   end

   if (200 == ReturnCode or ReturnCode == 201) then
      NamedControl.SetPosition("Connected", 1)
   else
      NamedControl.SetPosition("Connected", 0) 
   end

   local decodedJSON = json.decode(Data)
   local Household = decodedJSON.households

   if Household == nil then 
      NamedControl.SetText("Error", decodedJSON.fault.faultstring)
   end

   Decode_Household(Household)
   Get_Groups()
   Get_Play_Lists()
end

-- Similar to Household ID, speakers within a Household can be grouped togeather. 
function Group_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then
      print(Data)
   end

   local decodedJSON = json.decode(Data)
   local Error = decodedJSON.errorCode
   NamedControl.SetText("Error", Error)

   if Group_ID == nil then
      local Group = decodedJSON.groups
      Decode_Group(Group)
   end

   Get_Meta_Data()
end

function Player_Mute_Response()

   if debug then
      print(Data)
   end
   Allow_Mute_Update = true
end

-- Not currently used. Left to add later. 
-- function Get_Player_Volume_Response(Table, ReturnCode, Data, Error, Headers)

--    if debug then
--       --print(ReturnCode)
--       --print(Headers)
--       --print(Data)
--    end
   
--    local decodedJSON = json.decode(Data)
--    local info = json.decode(Data)
--    local Sonos_Mute_State = info.muted

--    if Sonos_Mute_State == false then
--       Sonos_Mute_State = 0
--    elseif Sonos_Mute_State == true then
--       Sonos_Mute_State = 1
--    end

--    if Allow_Mute_Update == true then
--       NamedControl.SetPosition("Mute", Sonos_Mute_State)
--    end

--    if Volume_State ~= info.volume then
--       NamedControl.SetValue("Volume", info.volume)
--       Volume_State = info.volume
--    end
-- end

-- This response returns a large amount of data, will use a lot of CPU resources.
function Get_Meta_Data_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then
     -- print(Data)
   end

   local info = json.decode(Data)

   local Album_Art = info.currentItem.track.imageUrl
   local Track = info.currentItem.track.name
   local Artist = info.currentItem.track.artist.name
   local Album = info.currentItem.track.album.name

   -- Some track can be missing a field. If so, the value of the last track would be stored, if nil, set to empty string.
   if Track == nil then Track = "" end
   if Artist == nil then Artist = "" end
   if Album == nil then Album = "" end

   NamedControl.SetText("Current_URL", Album_Art)
   NamedControl.SetText("Track", Track)
   NamedControl.SetText("Artist", Artist)
   NamedControl.SetText("Album", Album)
end

function Get_Play_Lists_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then
      print(Data)
   end

   local decodedJSON = json.decode(Data)
   -- Sets the Key as the ID number and the Value to the Playlist name.
   -- With this you can load the playlist based on key, and see the name of the playlist in the module.
   for i = 1,10 do
      if decodedJSON ~= nil then
         Playlists[tonumber(decodedJSON.playlists[i].id)] = decodedJSON.playlists[i].name
      end 
   end
   Update_Time = 1
end

function Load_Playlist_Response(Table, ReturnCode, Data, Error, Headers)

   if debug then
      print(Data)
   end
   Get_Meta_Data() -- Get metadata of first track in new playlist.
end
-- #endregion Responses. --


-- #region Decode JSON. --
-- Decode JSON in seperate functions here becuase they come from same eventhandler function.
-- Could do this differently, keeping it like this works for now.
function Decode_Household(Input)

   for k,v in ipairs(Input) do
      Household_ID = v.id
   end
end

function Decode_Group(Input)

   for k,v in ipairs(Input) do
      Group_ID = v.id
   end
end
-- #endregion Decode JSON. --

-- #region Get Auth token and Refresh token. -- 

-- Takes Client ID, and returns Auth tokens. 
function Authorization(ClientID, URI)

   local Token_Url = HttpClient.DecodeString(HttpClient.CreateUrl({
      Host = Host_Path,
      Path = "login/v3/oauth/access?grant_type=authorization_code&code=" .. ClientID .. "&redirect_uri=" .. URI}))

   HttpClient.Upload({
      Url = Token_Url,
      Headers =  {["Authorization"] = Authorization_Code},
      Data = "",
      Method = "POST",
      EventHandler = Authorization_Response})
end

--If needed or if Auth token expires, refresh the Auth token.
function Refresh()

   Refresh_Url = HttpClient.DecodeString(HttpClient.CreateUrl({
      Host = Host_Path,
      Path = "login/v3/oauth/access?grant_type=refresh_token&refresh_token=" .. Refresh_Token}))

   HttpClient.Upload({
      Url = Refresh_Url,
      Headers =  {["Authorization"] = Authorization_Code, ["Content-Type"] = "application/x-www-form-urlencoded;charset=utf-8"},
      Data = "",
      Method = "POST",
      EventHandler = Authorization_Response})
end
-- #endregion Get Auth token and Refresh token. -- 

-- #region Controls. --

--Change to next or previous track.
function Playback(Control)

   local Playback_Url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/playback/" .. Control)

   HttpClient.Upload({
      Url = Playback_Url,
      Headers = {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},           
      Data = json.encode({}),
      EventHandler = Group_Response})
end

function Player_Volume(Control)

   local Player_Volume_url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/groupVolume")
  
   HttpClient.Upload({
      Url = Player_Volume_url,
      Headers = {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},           
      Data = Control,
      EventHandler = Group_Response})
end

function Player_Mute(Control)

   Allow_Mute_Update = false
   local Player_Mute_url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/groupVolume/mute")

   HttpClient.Upload({
      Url = Player_Mute_url,
      Headers = {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},           
      Data = Control,
      EventHandler = Player_Mute_Response})
end

function Load_Playlist(pos)

   local Load_Playlist_url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/playlists")
   local Data_Table = {playlistId = format(pos), action = "replace"}
   local Data = json.encode(Data_Table)

   HttpClient.Upload({
      Url = Load_Playlist_url,
      Headers = {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},           
      Data = Data,
      EventHandler = Load_Playlist_Response})
end
-- #endregion Controls. --

--#region Get Requests. --
function Get_Households()

   local Households_Url = HttpClient.CreateUrl({
      Host = Control_Host_Path,
      Path = "/control/api/v1/households"})

      HttpClient.Upload({
         Url = Households_Url,
         Headers =  {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},
         Data = "",
         Method = "GET",
         EventHandler = Household_Response})
end

function Get_Groups()

   local Get_Groups_Url = HttpClient.CreateUrl({
      Host = Control_Host_Path,
      Path = "/control/api/v1/households/" .. Household_ID .. "/groups"})

      HttpClient.Upload({
         Url = Get_Groups_Url,
         Headers =  {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},
         Data = "",
         Method = "GET",
         EventHandler = Group_Response})
end

-- function Get_Player_Volume()

--    local Get_Player_Volume_url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/groupVolume")

--    HttpClient.Upload({
--       Url = Get_Player_Volume_url,
--       Headers = {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},           
--       Data = "",
--       EventHandler = Get_Player_Volume_Response,
--       Method = "GET"})
-- end

function Get_Meta_Data()

   local Get_Meta_Data_Url = (Control_Host_Path .. "/control/api/v1/groups/" ..Group_ID .. "/playbackMetadata")

   HttpClient.Upload({
         Url = Get_Meta_Data_Url,
         Headers =  {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},
         Data = "",
         Method = "GET",
         EventHandler = Get_Meta_Data_Response})
end

function Get_Play_Lists()
   
   local Get_Play_Lists_Url = (Control_Host_Path .. "/control/api/v1/households/" .. Household_ID .. "/playlists")

   HttpClient.Upload({
         Url = Get_Play_Lists_Url,
         Headers =  {["Authorization"] = "Bearer " .. Access_Token, ["Content-Type"] = "application/json"},
         Data = "",
         Method = "GET",
         EventHandler = Get_Play_Lists_Response})
end

function Play_List_Update(pos) 
   
   local Limit = tablelength(Playlists)
  
   if pos  >= Limit then
      NamedControl.SetValue("Playlist Select", Limit - 1)
   end

   for k,v in pairs(Playlists) do
      if k == pos then
         NamedControl.SetText("Playlists", v)
      end
   end
end
-- #endregion End get requests. --

function TimerClick()

   -- Round off volume value to whole number for Sonos.
   local Volume = math.floor(NamedControl.GetValue("Volume"))
   local Mute = NamedControl.GetPosition("Mute")
   local Playlist_Select = NamedControl.GetValue("Playlist Select")
   local Playlist_Name = NamedControl.GetText("Playlist")
   Count = Count + 1
   Vol_Count = Vol_Count + 1

   -- Refresh tokens 4 times a day. 
   for k,v in pairs(Token_Refresh_Times) do 
      if (os.date("%H:%M")) == v and Allow_Refresh == false then
         Refresh_Time = v
         Allow_Refresh = true
         if debug then print("Refresh!") end
         Refresh()
      elseif  (os.date("%H:%M")) ~= Refresh_Time then
         Allow_Refresh = false
      end
   end

   if NamedControl.GetValue("Connect") == 1 and Access_Token ~= nil then
      Update_Time = 2
      Get_Households()
      Playlists = {}
      Count = 0
      Vol_Count = 0
      NamedControl.SetValue("Connect", 0)
   end

   if NamedControl.GetValue("Authorize") == 1 and NamedControl.GetText("ClientID") ~= "" and Access_Token ~= nil then
      ClientID = NamedControl.GetText("ClientID")
      Authorization(ClientID, URI)
      NamedControl.SetValue("Authorize", 0)
   end

   if NamedControl.GetValue("Refresh") == 1 then
      Refresh()
      NamedControl.SetValue("Refresh", 0)
   end

   if Group_ID ~= nil then

      if NamedControl.GetPosition("Meta_Data") == 1 then
         Get_Meta_Data()
         NamedControl.SetPosition("Meta_Data", 0)
      end

      if NamedControl.GetPosition("Previous_Track") == 1 then
         Playback("skipToPreviousTrack")
         NamedControl.SetPosition("Previous_Track", 0)
      end

      if NamedControl.GetPosition("Next_Track") == 1 then
         Playback("skipToNextTrack")
         NamedControl.SetPosition("Next_Track", 0)
      end

      if NamedControl.GetPosition("Load Playlist") == 1 then
         Load_Playlist(Playlist_Select)
         NamedControl.SetPosition("Load Playlist", 0)
      end

      if NamedControl.GetPosition("Play") ~= Play_State then
         Play_State = NamedControl.GetPosition("Play")
         if Play_State == 1 then
            Playback("pause")
         elseif Play_State == 0 then
            Playback("play")
         end
      end

      if Volume ~= Volume_State and Scroll_Lock == false then
         Scroll_Lock = true
         NamedControl.SetPosition("Mute", 0)
         local JSON_Volume = {volume = Volume}
         local encodedString = json.encode(JSON_Volume)
         Player_Volume(encodedString)
         Volume_State = Volume
      end
   
      if Mute ~= Mute_State then
         Allow_Mute_Update = false
         Mute_State = Mute
            if Mute_State == 1 then
                  JSON_Mute = {muted = true}
            elseif Mute_State == 0 then
                  JSON_Mute = {muted = false}
            end
         local encodedString = json.encode(JSON_Mute)
         Player_Mute(encodedString)
      end

      if Playlist_Select ~= Playlist_Select_State then
         Playlist_Select_State = Playlist_Select
         Play_List_Update(Playlist_Select) 
      end
      
      -- Timer to get Meta Data.
      if Count == 30 then
         Get_Meta_Data()
         Count = 0
      end

      -- Timer to get volume and mute state of the Sonos app.
      -- for k,v in pairs(Sonos_Table) do
      --    if Count == v and Allow_Mute_Update ~= false then
      --       Get_Player_Volume()
      --    end
      -- end

      -- Timer to allow volume change.
      if Vol_Count == 4 then
         Vol_Count = 0
      elseif Vol_Count == 3 then
         Scroll_Lock = false
      end
   end
end

MyTimer = Timer.New()
MyTimer.EventHandler = TimerClick
MyTimer:Start(Update_Time)
