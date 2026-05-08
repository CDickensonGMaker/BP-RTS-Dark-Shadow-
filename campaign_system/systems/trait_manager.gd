## TraitManager - Handles loading, assignment, and progression of general traits.
## Loads all trait resources from campaign_system/data/traits/ at runtime.
## Part of Phase 9 General Trait System.
## NOTE: No class_name to avoid load-order issues with GeneralTrait/GeneralProfile references.
extends Node

const TRAITS_PATH: String = "res://campaign_system/data/traits/"
const STARTING_TRAIT_COUNT: int = 2

## All available traits, keyed by trait_id.
var all_traits: Dictionary = {}  # trait_id -> GeneralTrait

## Traits organized by category for quick lookup.
var traits_by_category: Dictionary = {}  # Category -> Array[GeneralTrait]


func _ready() -> void:
	_load_all_traits()


## Load all trait .tres files from the traits directory.
func _load_all_traits() -> void:
	all_traits.clear()
	traits_by_category.clear()

	# Initialize category arrays
	# Categories: LEADERSHIP=0, TACTICAL=1, HATRED=2, COMMAND=3, PERSONALITY=4
	for cat in range(5):
		traits_by_category[cat] = []

	# Scan traits directory
	var dir := DirAccess.open(TRAITS_PATH)
	if not dir:
		push_error("TraitManager: Could not open traits directory: %s" % TRAITS_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var trait_path := TRAITS_PATH + file_name
			var t = load(trait_path)
			if t and t.trait_id != "":
				all_traits[t.trait_id] = t
				traits_by_category[t.category].append(t)
				print("[TraitManager] Loaded trait: %s (%s)" % [t.trait_name, t.trait_id])
			else:
				push_warning("TraitManager: Invalid trait file: %s" % trait_path)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[TraitManager] Loaded %d traits total" % all_traits.size())


## Generate starting traits for a new general.
## Returns 3 random non-conflicting traits that are not unlockables.
func generate_starting_traits() -> Array:
	var result: Array = []
	var available: Array = []

	# Gather all non-unlockable traits
	for t in all_traits.values():
		if not t.is_unlockable:
			available.append(t)

	# Shuffle for randomness
	available.shuffle()

	# Pick STARTING_TRAIT_COUNT non-conflicting traits
	for t in available:
		if result.size() >= STARTING_TRAIT_COUNT:
			break

		# Check conflicts with already selected traits
		var has_conflict := false
		for selected in result:
			if t.conflicts_with_trait(selected):
				has_conflict = true
				break

		if not has_conflict:
			result.append(t)

	return result


## Get a trait by ID.
func get_trait(trait_id: String):
	return all_traits.get(trait_id, null)


## Get all traits of a specific category.
func get_traits_by_category(category: int) -> Array:
	return traits_by_category.get(category, [])


## Get traits available for unlock based on profile's progression.
func get_available_traits_for_unlock(profile) -> Array:
	var result: Array = []

	for t in all_traits.values():
		# Skip if already has this trait
		if profile.has_trait(t.trait_id):
			continue

		# Skip if conflicts with existing traits
		if not profile.can_add_trait(t):
			continue

		# Check unlock requirements
		if t.is_unlockable:
			if not t.can_unlock(profile.battles_fought, profile.total_kills):
				continue
			# Also check if already unlocked (skip if not yet unlocked)
			if t.trait_id in profile.unlocked_traits:
				continue

		result.append(t)

	return result


## Get traits that can be unlocked with current progression (but haven't been yet).
func get_unlockable_traits(profile) -> Array:
	var result: Array = []

	for t in all_traits.values():
		# Must be an unlockable trait
		if not t.is_unlockable:
			continue

		# Must meet requirements
		if not t.can_unlock(profile.battles_fought, profile.total_kills):
			continue

		# Must not already be unlocked
		if t.trait_id in profile.unlocked_traits:
			continue

		# Must not already have this trait
		if profile.has_trait(t.trait_id):
			continue

		result.append(t)

	return result


## Unlock a trait for a profile.
func unlock_trait(profile, trait_id: String) -> bool:
	var t = get_trait(trait_id)
	if not t:
		return false

	if not t.is_unlockable:
		return false

	if not t.can_unlock(profile.battles_fought, profile.total_kills):
		return false

	if trait_id in profile.unlocked_traits:
		return false

	profile.unlocked_traits.append(trait_id)
	print("[TraitManager] %s unlocked trait: %s" % [profile.general_name, t.trait_name])
	return true


## Load traits for a profile from save data trait IDs.
func load_profile_traits(profile, trait_ids: Array) -> void:
	profile.traits.clear()
	for trait_id in trait_ids:
		var t = get_trait(trait_id)
		if t:
			profile.traits.append(t)
		else:
			push_warning("TraitManager: Unknown trait ID in save data: %s" % trait_id)


## Create a new GeneralProfile with random starting traits.
func create_general(general_name: String):
	var GeneralProfileScript = load("res://campaign_system/data/general_profile.gd")
	var profile = GeneralProfileScript.new()
	profile.general_name = general_name
	profile.traits = generate_starting_traits()
	return profile


## Get all trait IDs as an array (for debugging/UI).
func get_all_trait_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in all_traits.keys():
		ids.append(id)
	return ids


## Get conflict info for a trait (for UI display).
func get_conflict_info(trait_id: String) -> Array[String]:
	var t = get_trait(trait_id)
	if not t:
		return []

	var conflicting_names: Array[String] = []
	for conflict_id in t.conflicts_with:
		var conflict_trait = get_trait(conflict_id)
		if conflict_trait:
			conflicting_names.append(conflict_trait.trait_name)
		else:
			conflicting_names.append(conflict_id)

	return conflicting_names
