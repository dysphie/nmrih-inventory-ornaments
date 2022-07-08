#include <sdktools>

#define MAX_BOUNDARY_ITEMS 10

StringMap objectiveItems;

void ObjectiveItems_OnPluginStart()
{
	objectiveItems = new StringMap();
	HookEntityOutput("nmrih_objective_boundary", "OnObjectiveBegin", OnBoundaryActivated);
}

void OnBoundaryActivated(const char[] output, int boundary, int activator, float delay)
{
	objectiveItems.Clear();

	char names[MAX_BOUNDARY_ITEMS][64];
	int colors[MAX_BOUNDARY_ITEMS];

	// This is ugly but faster than iterating!
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[0]", names[0], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[1]", names[1], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[2]", names[2], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[3]", names[3], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[4]", names[4], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[5]", names[5], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[6]", names[6], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[7]", names[7], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[8]", names[8], sizeof(names[]));
	GetEntPropString(boundary, Prop_Data, "m_szGlowEntityNames[9]", names[9], sizeof(names[]));
	colors[0] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[0]");
	colors[1] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[1]");
	colors[2] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[2]");
	colors[3] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[3]");
	colors[4] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[4]");
	colors[5] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[5]");
	colors[6] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[6]");
	colors[7] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[7]");
	colors[8] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[8]");
	colors[9] = GetEntProp(boundary, Prop_Data, "m_GlowEntityColors[9]");

	for (int i = 0; i < MAX_BOUNDARY_ITEMS; i++)
	{
		if (strlen(names[i]) > 0)
		{
			objectiveItems.SetValue(names[i], colors[i]);
		}
	}

	// Force clients to re-render any objective items they have to remove old glows
	ForceUpdateRenderers();
}

bool GetEntityObjectiveColor(int entity, int& color = 0)
{
	char targetname[64];
	GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
	return objectiveItems.GetValue(targetname, color);
}