#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include "nmrih-inventory-ornaments/objective-items.sp"

#pragma semicolon 1

#define BODY_NOMAGLITE 1
#define SPECMODE_FIRSTPERSON 4

#define PLUGIN_VERSION "0.1.3"
#define PLUGIN_DESCRIPTION "Displays inventory items on player characters"

public Plugin myinfo = 
{
	name = "[NMRiH] Inventory Ornaments",
	author = "Dysphie",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://github.com/dysphie/nmrih-inventory-ornaments"
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
	int propRef; // Reference to our ornament prop
	int activeLayer;
	int weaponRef; // Reference to the weapon we are rendering

	void Reset()
	{
		int prop = EntRefToEntIndex(this.propRef);

		if (prop != -1)
			SafeRemoveEntity(prop);

		this.Init();
	}

	void Init()
	{
		this.propRef = INVALID_ENT_REFERENCE;
		this.weaponRef = INVALID_ENT_REFERENCE;
		this.activeLayer = -1;
	}

	void Update()
	{
		int prop = EntRefToEntIndex(this.propRef);
		if (prop == -1)
		{
			PrintToServer("Got invalid propRef");
			return;
		}

		int weapon = EntRefToEntIndex(this.weaponRef);
		int color;
		if (weapon == -1 || !GetEntityObjectiveColor(weapon, color))
		{
			SetVariantString("!activator");
			AcceptEntityInput(prop, "DisableGlow", prop, prop);
		}
		else
		{
			GlowEntity(prop, color);
		}
	}

	void Draw(int client, int weapon, int layer, const char[] classname)
	{
		int prop = EntRefToEntIndex(this.propRef);

		if (prop == -1)
		{
			char model[PLATFORM_MAX_PATH];
			GetEntityModel(weapon, model, sizeof(model));
		
			prop = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(prop, "model", model);
			DispatchKeyValue(prop, "spawnflags", "256");
			DispatchKeyValue(prop, "solid", "0");
			DispatchSpawn(prop);

			SetEntPropString(prop, Prop_Data, "m_iClassname", "inventory_ornament");

			// FIXME: Add this back!
			// SDKHook(prop, SDKHook_SetTransmit, OnOrnamentTransmit);

			SetEntPropEnt(prop, Prop_Send, "m_hOwnerEntity", client);
			SetVariantString("!activator");
			AcceptEntityInput(prop, "SetParent", client);
			SetVariantString("HipAttachmentRight");
			AcceptEntityInput(prop, "SetParentAttachment");
			AcceptEntityInput(prop, "DisableShadows");

			this.propRef = EntIndexToEntRef(prop);
		}
		
		WeaponPlaceInfo wpi;
		weaponPlaceInfo.GetArray(classname, wpi, sizeof(wpi));
		TeleportEntity(prop, .origin = wpi.offset, .angles = wpi.angles);
		SetEntPropFloat(prop, Prop_Send, "m_flModelScale", wpi.scale);

		int modelIndex = GetModelIndex(weapon);
		SetModelIndex(prop, modelIndex);
		SetEntProp(prop, Prop_Send, "m_nBody", BODY_NOMAGLITE);
		this.activeLayer = layer;

		int color;
		if (GetEntityObjectiveColor(weapon, color))
		{
			GlowEntity(prop, color);
		}

		this.weaponRef = EntIndexToEntRef(weapon); 
	}
}

void GlowEntity(int entity, int color)
{
	DispatchKeyValue(entity, "glowable", "1"); 
	DispatchKeyValue(entity, "glowblip", "0");
	SetEntProp(entity, Prop_Data, "m_clrGlowColor", color);
	DispatchKeyValue(entity, "glowdistance", "90");

	SetVariantString("!activator");
	AcceptEntityInput(entity, "enableglow", entity, entity);
}

public void OnPluginStart()
{
	CreateConVar("nmr_inventory_ornaments_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION,
    	FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	weaponRenderInfo = new StringMap();
	weaponPlaceInfo = new StringMap();	
	ParseConfig();

	ObjectiveItems_OnPluginStart();

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
		renderers[client].SetArray(i, renderer); // ?? This wasn't here before, how did it even work before, did it not?
	}
}

void ForceUpdateRenderers()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if (!renderers[client])
				continue;

			Renderer renderer;
			for (int i; i < maxRenderers; i++)
			{
				renderers[client].GetArray(i, renderer);
				renderer.Update();
				PrintToServer("Forcing update on %N's renderer", client);
				renderers[client].GetArray(i, renderer);
			}
		}
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

Action OnWeaponDrop(int client, int weapon)
{
	if (weapon != -1 && weapon != GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
		OnWeaponUnholstered(client, weapon);

	return Plugin_Continue;
}

void OnWeaponEquipPost(int client, int weapon)
{
	if (weapon != -1 && weapon != GetActiveWeapon(client))
		OnWeaponHolstered(client, weapon);
}

Action OnWeaponSwitch(int client, int weapon)
{
	int curWeapon = GetActiveWeapon(client);

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
	int activeWeapon = GetActiveWeapon(client);

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
	if (entity >= 0 && entity <= MaxClients)
	{
		ThrowError("Attempted to delete player or world entity %d. Tell a developer", entity);
	}
	RemoveEntity(entity);
}

int GetActiveWeapon(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
}