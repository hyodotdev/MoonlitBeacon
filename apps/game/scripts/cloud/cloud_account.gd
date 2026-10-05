extends RefCounted

## Account-data deletion in ONE atomic commit. Runs before Firebase Auth
## deletion so no cloud row is orphaned.
##
## The commit deletes Hall, checkpoint, reservation, and profile together.
## Atomicity is the crash guarantee: a kill mid-run leaves either all four
## rows or none of them, never a living profile claiming an ID whose
## reservation is gone (which another account could then re-register). The
## rules enforce the same pairing server-side: living pair halves go only
## together with the Hall row already gone. Missing rows are server no-ops,
## so repeating the commit after a crash or a failure is safe.
##
## Only the native identity layer deletes the Firebase Auth user, and only
## after this commit is acknowledged. This helper reports ok solely on that
## acknowledgement, with explicit failure codes otherwise.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const STEP_HALL: String = "hall"
const STEP_CHECKPOINT: String = "checkpoint"
const STEP_RESERVATION: String = "reservation"
const STEP_PROFILE: String = "profile"


## Ordered deletion steps for one account. Used by the commit builder below
## and by the author runbook so the two cannot drift apart.
static func deletion_plan(uid: String, public_id: String) -> Array:
	return [
		{
			"step": STEP_HALL,
			"path": "documents/%s/%s" % [
				CloudSchema.HALL_COLLECTION, public_id],
		},
		{
			"step": STEP_CHECKPOINT,
			"path": "documents/%s/%s" % [
				CloudSchema.CHECKPOINT_COLLECTION, uid],
		},
		{
			"step": STEP_RESERVATION,
			"path": "documents/%s/%s" % [
				CloudSchema.RESERVATION_COLLECTION, public_id],
		},
		{
			"step": STEP_PROFILE,
			"path": "documents/%s/%s" % [
				CloudSchema.PROFILE_COLLECTION, uid],
		},
	]


## Commit body deleting every plan step at once. No preconditions: missing
## rows delete as no-ops on the server and the rules allow them, which keeps
## repeats idempotent.
static func deletion_commit_body(uid: String, public_id: String) -> Dictionary:
	var writes: Array = []
	for step in deletion_plan(uid, public_id):
		writes.append({
			"delete": "projects/%s/databases/%s/%s" % [
				CloudSchema.PROJECT_ID, CloudSchema.DATABASE_ID,
				str(step.get("path", ""))],
		})
	return {"writes": writes}


static func _step_names() -> Array[String]:
	return [STEP_HALL, STEP_CHECKPOINT, STEP_RESERVATION, STEP_PROFILE]


func delete_account_data(transport: RefCounted, uid: String,
		public_id: String) -> Dictionary:
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid",
			"retryable": false}
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var reply: Dictionary = await transport.call("post", "documents:commit",
		JSON.stringify(deletion_commit_body(uid, public_id)))
	if str(reply.get("status", "")) == "ok":
		return {"status": "ok", "completed": _step_names(), "remaining": []}
	return {
		"status": str(reply.get("status", "failure")),
		"code": str(reply.get("code", "delete-failed")),
		"retryable": bool(reply.get("retryable", false)),
		"completed": [],
		"remaining": _step_names(),
	}
