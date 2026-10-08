extends RefCounted

## Account-data deletion in ONE atomic commit. Runs before Firebase Auth
## deletion so no cloud row is orphaned.
##
## The commit deletes Hall, name claim, adventurer, checkpoint, attendance,
## reservation, and profile together. Atomicity is the crash guarantee: a
## kill mid-run leaves either all seven rows or none of them, never a
## living profile claiming an ID whose reservation is gone (which another
## account could then re-register) and never a freed name under a living
## score. The rules enforce the same pairing server-side: living pair
## halves go only together with the Hall row already gone, and the
## attendance row goes with the canonical halves. Missing rows are server
## no-ops, so repeating the commit after a crash or a failure is safe.
## Unnamed accounts commit the five legacy steps unchanged.
##
## Only the native identity layer deletes the Firebase Auth user, and only
## after this commit is acknowledged. This helper reports ok solely on that
## acknowledgement, with explicit failure codes otherwise.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")
const CloudName: Script = preload("res://scripts/cloud/cloud_name.gd")

const STEP_HALL: String = "hall"
const STEP_NAME: String = "name"
const STEP_ADVENTURER: String = "adventurer"
const STEP_CHECKPOINT: String = "checkpoint"
const STEP_ATTENDANCE: String = "attendance"
const STEP_RESERVATION: String = "reservation"
const STEP_PROFILE: String = "profile"


## Ordered deletion steps for one account. Used by the commit builder below
## and by the author runbook so the two cannot drift apart. The name key
## rides along when the account claimed one; empty omits the pair.
static func deletion_plan(uid: String, public_id: String,
		name_key: String = "") -> Array:
	var steps: Array = [
		{
			"step": STEP_HALL,
			"path": "documents/%s/%s" % [
				CloudSchema.HALL_COLLECTION, public_id],
		},
	]
	if not name_key.is_empty():
		steps.append({
			"step": STEP_NAME,
			"path": "documents/%s/%s" % [
				CloudSchema.NAME_COLLECTION, name_key],
		})
		steps.append({
			"step": STEP_ADVENTURER,
			"path": "documents/%s/%s" % [
				CloudSchema.ADVENTURER_COLLECTION, public_id],
		})
	steps.append({
		"step": STEP_CHECKPOINT,
		"path": "documents/%s/%s" % [
			CloudSchema.CHECKPOINT_COLLECTION, uid],
	})
	steps.append({
		"step": STEP_ATTENDANCE,
		"path": "documents/%s/%s" % [
			CloudSchema.ATTENDANCE_COLLECTION, public_id],
	})
	steps.append({
		"step": STEP_RESERVATION,
		"path": "documents/%s/%s" % [
			CloudSchema.RESERVATION_COLLECTION, public_id],
	})
	steps.append({
		"step": STEP_PROFILE,
		"path": "documents/%s/%s" % [
			CloudSchema.PROFILE_COLLECTION, uid],
	})
	return steps


## Commit body deleting every plan step at once. No preconditions: missing
## rows delete as no-ops on the server and the rules allow them, which keeps
## repeats idempotent.
static func deletion_commit_body(uid: String, public_id: String,
		name_key: String = "") -> Dictionary:
	var writes: Array = []
	for step in deletion_plan(uid, public_id, name_key):
		writes.append({
			"delete": "projects/%s/databases/%s/%s" % [
				CloudSchema.PROJECT_ID, CloudSchema.DATABASE_ID,
				str(step.get("path", ""))],
		})
	return {"writes": writes}


static func _step_names(name_key: String = "") -> Array[String]:
	if name_key.is_empty():
		return [STEP_HALL, STEP_CHECKPOINT, STEP_ATTENDANCE,
			STEP_RESERVATION, STEP_PROFILE]
	return [STEP_HALL, STEP_NAME, STEP_ADVENTURER, STEP_CHECKPOINT,
		STEP_ATTENDANCE, STEP_RESERVATION, STEP_PROFILE]


## Delete one account's owned rows. An empty key resolves the claimed name
## first: found rows join the same commit, a missing adventurer keeps the
## legacy five-step commit, and a resolution failure stops before any
## delete so a wrong key can never strand the real name.
func delete_account_data(transport: RefCounted, uid: String,
		public_id: String, name_key: String = "") -> Dictionary:
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid",
			"retryable": false}
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var key: String = name_key
	if key.is_empty():
		var names: RefCounted = CloudName.new()
		var resolved: Dictionary = await names.call(
			"fetch_adventurer", transport, uid, public_id)
		if str(resolved.get("status", "")) == "ok":
			key = str(resolved.get("key", ""))
		elif str(resolved.get("code", "")) != "adventurer-not-found":
			return {
				"status": str(resolved.get("status", "failure")),
				"code": str(resolved.get("code", "delete-failed")),
				"retryable": bool(resolved.get("retryable", false)),
				"completed": [],
				"remaining": _step_names(),
			}
	var reply: Dictionary = await transport.call("post", "documents:commit",
		JSON.stringify(deletion_commit_body(uid, public_id, key)))
	if str(reply.get("status", "")) == "ok":
		return {"status": "ok", "completed": _step_names(key),
			"remaining": []}
	return {
		"status": str(reply.get("status", "failure")),
		"code": str(reply.get("code", "delete-failed")),
		"retryable": bool(reply.get("retryable", false)),
		"completed": [],
		"remaining": _step_names(key),
	}
