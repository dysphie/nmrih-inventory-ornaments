#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1

#define SOLID_NONE 0
#define COLLISION_GROUP_NONE 0
#define BODY_NOMAGLITE 1
#define SPECMODE_FIRSTPERSON 4

#define ASSERT(%1) if (!%1) ThrowError("#%1")

public Plugin myinfo = 
{
	name = "[NMRiH] Inventory Ornaments",
	author = "Dysphie",
	description = "Displays inventory items on player characters",
	version = "0.1.2",
	url = ""
};

StringMap weaponRenderInfo;
StringMap weaponPlaceInfo;
int maxRenderers;

enum struct WeaponRenderInfo
{
	int rendererID;
	int layer;
}

enum struct WeaponPlaceInfo
{
	char attachment[32];
	float offset[3];
	float angles[3];
	float scale;
}

enum struct Renderer
{
	bool overridden;
	int propref;
	int activeLayer;

	void Reset()
	{
		int prop = EntRefToEntIndex(this.propref);

		if (prop != -1)
			SafeRemoveEntity(prop);

		this.Init();
	}

	void Init()
	{
		this.propref = INVALID_ENT_REFERENCE;
		this.activeLayer = -1;
	}

	void Draw(int client, int weapon, int layer, const char[] classname)
	{
		int prop = EntRefToEntIndex(this.propref);

		if (prop == -1)
		{
			char model[PLATFORM_MAX_PATH];
			GetEntityModel(weapon, model, sizeof(model));
		
			prop = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(prop, "model", model);
			DispatchKeyValue(prop, "spawnflags", "256");
			DispatchKeyValue(prop, "solid", "0");
			DispatchSpawn(prop);

			SDKHook(prop, SDKHook_SetTransmit, OnOrnamentTransmit);

			SetEntPropEnt(prop, Prop_Send, "m_hOwnerEntity", client);
			SetVariantString("!activator");
			AcceptEntityInput(prop, "SetParent", client);
			SetVariantString("HipAttachmentRight");
			AcceptEntityInput(prop, "SetParentAttachment");
			AcceptEntityInput(prop, "DisableShadows");

			this.propref = EntIndexToEntRef(prop);
		}
		
		WeaponPlaceInfo wpi;
		weaponPlaceInfo.GetArray(classname, wpi, sizeof(wpi));
		TeleportEntity(prop, .origin = wpi.offset, .angles = wpi.angles);
		SetEntPropFloat(prop, Prop_Send, "m_flModelScale", wpi.scale);

		int modelIndex = GetModelIndex(weapon);
		SetModelIndex(prop, modelIndex);
		SetEntProp(prop, Prop_Send, "m_nBody", BODY_NOMAGLITE);
		this.activeLayer = layer;
	}
}

public void OnPluginStart()
{
	weaponRenderInfo = new StringMap();
	weaponPlaceInfo = new StringMap();	
	ParseConfig();

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_extracted", OnPlayerExtracted);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Pre);
}

public Action OnOrnamentTransmit(int ornament, int transmitee)
{
	// Hide ornament to wearer
	int ornamentWearer = GetEntPropEnt(ornament, Prop_Data, "m_hOwnerEntity");
	if (transmitee == ornamentWearer)
		return Plugin_Handled;

	// Hide ornament to specs observing wearer in first person
	int observerMode = GetEntProp(transmitee, Prop_Send, "m_iObserverMode");
	if (observerMode != SPECMODE_FIRSTPERSON)
		return Plugin_Continue;

	int observerTarget = GetEntPropEnt(transmitee, Prop_Send, "m_hObserverTarget");
	if (observerTarget == ornamentWearer)
		return Plugin_Handled;

	return Plugin_Continue;
}

ArrayList renderers[MAXPLAYERS+1];

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			ResetClientRenderers(i);
}

void ParseConfig()
{
	char cfg[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cfg, sizeof(cfg), "configs/inventory-ornaments.cfg");

	KeyValues kv = new KeyValues("Ornaments");
	if (!kv.ImportFromFile(cfg))
		SetFailState("Couldn't read from \"%s\"", cfg);

	if (!kv.GotoFirstSubKey())
	{
		delete kv;
		return;
	}

	char rendererName[64];
	char itemName[80];

	int rendererID;
	do
	{
		kv.GetSectionName(rendererName, sizeof(rendererName));

		WeaponPlaceInfo baseWpi;
		kv.GetVector("offset", baseWpi.offset);
		kv.GetVector("rotation", baseWpi.angles);
		baseWpi.scale = kv.GetFloat("scale", 1.0);
		kv.GetString("attachment", baseWpi.attachment, sizeof(baseWpi.attachment));

		if (!kv.JumpToKey("items")) // Slot with no items, bail
			continue;

		if (!kv.GotoFirstSubKey()) // Slot with no items, bail
		{
			kv.GoBack();
			continue;
		}
		
		int layerID = 0;

		do
		{
			WeaponPlaceInfo itemWpi;
			kv.GetSectionName(itemName, sizeof(itemName));


			kv.GetVector("offset", itemWpi.offset, baseWpi.offset);
			kv.GetVector("rotation", itemWpi.angles, baseWpi.angles);
			itemWpi.scale = kv.GetFloat("scale", baseWpi.scale);
			kv.GetString("attachment", itemWpi.attachment, sizeof(itemWpi.attachment), baseWpi.attachment);

			weaponPlaceInfo.SetArray(itemName, itemWpi, sizeof(itemWpi));

			WeaponRenderInfo itemWri;
			itemWri.rendererID = rendererID;
			itemWri.layer = layerID;
			weaponRenderInfo.SetArray(itemName, itemWri, sizeof(itemWri));
			layerID++;

		} 
		while (kv.GotoNextKey());

		kv.GoBack();
		kv.GoBack();
		rendererID++;

	} 
	while (kv.GotoNextKey());

	maxRenderers = rendererID;
	delete kv;
}

public void OnPlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	ResetClientRenderers(event.GetInt("player_id"));
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		ResetClientRenderers(client);
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		ResetClientRenderers(client);

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	InitClientRenderers(client);
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
}

void ResetClientRenderers(int client)
{
	if (!renderers[client])
		return;

	Renderer renderer;
	for (int i; i < maxRenderers; i++)
	{
		renderers[client].GetArray(i, renderer);
		renderer.Reset();
	}
}

void InitClientRenderers(int client)
{
	renderers[client] = new ArrayList(sizeof(Renderer));

	Renderer r;
	for (int i; i < maxRenderers; i++)
	{
		r.Init();
		renderers[client].PushArray(r);
	}
}

public void OnClientDisconnect(int client)
{
	ResetClientRenderers(client);
	delete renderers[client];
}

public Action OnWeaponDrop(int client, int weapon)
{
	if (weapon == -1)
		return Plugin_Continue;
	
	if (weapon != -1 && weapon != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		OnWeaponUnholstered(client, weapon);

	return Plugin_Continue;
}

public void OnWeaponEquipPost(int client, int weapon)
{
	if (weapon != -1 && weapon != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		OnWeaponHolstered(client, weapon);
}

public Action OnWeaponSwitch(int client, int weapon)
{
	int curWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if (curWeapon == weapon)
		return Plugin_Continue;

	if (weapon != -1)
		OnWeaponUnholstered(client, weapon);

	if (curWeapon != -1)
		OnWeaponHolstered(client, curWeapon);

	return Plugin_Continue;
}

void OnWeaponHolstered(int client, int weapon)
{
	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));

	WeaponRenderInfo wri = {-1, -1};
	if (!weaponRenderInfo.GetArray(classname, wri, sizeof(wri)))
		return;

	Renderer renderer;
	renderers[client].GetArray(wri.rendererID, renderer);

	if (renderer.activeLayer == -1 || wri.layer < renderer.activeLayer)
	{	
		renderer.Draw(client, weapon, wri.layer, classname);
		renderers[client].SetArray(wri.rendererID, renderer);
	}
}

void OnWeaponUnholstered(int client, int weapon)
{
	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));

	WeaponRenderInfo wri = {-1, -1};
	if (!weaponRenderInfo.GetArray(classname, wri, sizeof(wri)))
		return;

	Renderer renderer;
	renderers[client].GetArray(wri.rendererID, renderer);

	if (renderer.activeLayer == wri.layer)
	{
		int layer;
		int newWep = FindWeaponForRenderer(client, wri.rendererID, weapon, layer);
		if (newWep == -1)
		{
			renderer.Reset();
		}
		else
		{
			GetEntityClassname(newWep, classname, sizeof(classname));
			renderer.Draw(client, newWep, layer, classname);
		}

		renderers[client].SetArray(wri.rendererID, renderer);	
	}
}

int FindWeaponForRenderer(int client, int rendererID, int except, int& layer)
{
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	static int max;
	max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");

	int bestWeapon = -1;
	int lowestLayer = 9999999;

	int weapon;
	WeaponRenderInfo wri = {-1, -1};

	char classname[32];

	for(int i; i < max; i++)
	{
		weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon == except || weapon == -1 || weapon == activeWeapon) 
			continue;

		GetEntityClassname(weapon, classname, sizeof(classname));
		weaponRenderInfo.GetArray(classname, wri, sizeof(wri));

		if (wri.rendererID != rendererID)
			continue;

		if (wri.layer < lowestLayer)
		{
			lowestLayer = wri.layer;
			bestWeapon = weapon;
		}
	}

	if (bestWeapon != -1)
		layer = lowestLayer;
	
	return bestWeapon;
}

void GetEntityModel(int entity, char[] buffer, int maxlen)
{
	GetEntPropString(entity, Prop_Data, "m_ModelName", buffer, maxlen);
}

int GetModelIndex(int entity)
{
	return GetEntProp(entity, Prop_Send, "m_iWorldModelIndex");
}

void SetModelIndex(int entity, int index)
{
	SetEntProp(entity, Prop_Send, "m_nModelIndex", index);
}

void SafeRemoveEntity(int entity)
{
	if (entity <= MaxClients)
		ThrowError("Entity %d is not removable", entity);
	RemoveEntity(entity);
}
