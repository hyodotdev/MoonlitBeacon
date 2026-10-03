#pragma once

// Godot-facing declaration of the iOS identity bridge. The implementation in
// ../src/MoonlitIdentityIos.mm talks to GoogleSignIn (ordinary Google
// account), AuthenticationServices (Sign in with Apple, SHA-256 nonce), and
// Firebase Auth. This header stays pure C++ so the GDExtension binding layer
// never includes Apple, Google, or Firebase headers.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

class MoonlitIdentityIos : public godot::Object {
	GDCLASS(MoonlitIdentityIos, godot::Object)

public:
	MoonlitIdentityIos();
	~MoonlitIdentityIos();

	static void _bind_methods();

	godot::String moonlitSignInGuest(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitSignInProvider(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitLinkProvider(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitGetSession(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitGetIdToken(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitSignOut(const godot::String &p_request_id,
		const godot::String &p_args_json);
	godot::String moonlitDeleteAccount(const godot::String &p_request_id,
		const godot::String &p_args_json);
	// Answers `cancelled` while no mutation began, `draining` once one did.
	godot::String moonlitCancelRequest(const godot::String &p_request_id);

	// Deferred emission point. Native SDK callbacks (main queue) never emit
	// the Godot signal directly; they call_deferred into this method, which
	// runs on the Godot thread.
	void _emit_outcome(const godot::String &p_outcome_json);

private:
	// Opaque Objective-C worker (MoonlitIdentityWorker *). Kept as void * so
	// no Apple type leaks into the C++ binding surface.
	void *_worker;
};
