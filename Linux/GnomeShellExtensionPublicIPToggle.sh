#!/usr/bin/env bash
# deploy.sh — deploy the "Public IP & Flag" GNOME Shell extension from scratch
#
# Features (this version):
#   * Panel shows: <flag emoji> <public IP>   (top bar, right side)
#   * LEFT-click  : toggle IP hidden <-> visible, PERSISTENT across logins
#                   (state stored in ~/.config/public-ip-flag/state.json,
#                    which this script deliberately never touches)
#   * RIGHT-click : refresh immediately (also auto-refreshes every 5 min)
#
# Run as your NORMAL user (no sudo):
#   chmod +x deploy.sh
#   ./deploy.sh

set -euo pipefail

UUID="public-ip-flag@gnome-shell-extensions"
EXT_BASE="$HOME/.local/share/gnome-shell/extensions"
EXT_DIR="$EXT_BASE/$UUID"

log()  { printf '%s\n' "==> $*"; }
ok()   { printf '%s\n' "OK: $*"; }
warn() { printf '%s\n' "!! $*"; }
die()  { printf '%s\n' "ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

enable_ext()  { gnome-extensions enable "$UUID" 2>/dev/null; }
ext_state()   { gnome-extensions info "$UUID" 2>/dev/null | sed -nE 's/^[[:space:]]*State:[[:space:]]*//p'; }
is_active()   { [[ "$(ext_state)" == "ENABLED" ]]; }
shell_knows() { gnome-extensions list 2>/dev/null | grep -qF "$UUID"; }

show_journal_errors() {
    warn "Recent shell log lines mentioning the extension or JS errors:"
    local jrnl
    if jrnl="$(journalctl --user -b --no-pager -n 800 2>/dev/null)"; then :; else
        jrnl="$(journalctl -b --no-pager -n 800 2>/dev/null || true)"
    fi
    printf '%s\n' "$jrnl" | grep -iE 'public-ip-flag|JS ERROR|JS WARNING' | tail -n 30 || true
}

finish_success() {
    echo
    ok "Extension is ENABLED with the new click-to-hide feature."
    echo "    Top bar, right side:  <flag> <public IP>"
    echo "      LEFT-click  = hide/show the IP (persists across logins)"
    echo "      RIGHT-click = refresh now"
    echo "    Test it now: left-click the IP once — it should turn into bullets."
    exit 0
}

# ---------------------------------------------------------------- phase 0: preflight
[[ $EUID -ne 0 ]] || die "Do NOT run with sudo — GNOME extensions install per-user. Run as your desktop user."
have gnome-shell      || die "gnome-shell not found in PATH."
have gnome-extensions || die "gnome-extensions not found in PATH."

SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
if [[ "$SESSION_TYPE" == "unknown" && -n "${XDG_SESSION_ID:-}" ]] && have loginctl; then
    SESSION_TYPE="$(loginctl show-session "$XDG_SESSION_ID" -p Type --value 2>/dev/null || echo unknown)"
fi

SHELL_MAJOR="$(gnome-shell --version 2>/dev/null | sed -nE 's/^GNOME Shell ([0-9]+).*/\1/p')"
[[ -n "$SHELL_MAJOR" ]] || SHELL_MAJOR="43"
[[ "$SHELL_MAJOR" -lt 45 ]] || die "GNOME $SHELL_MAJOR requires ESM-format extensions; this deploys the legacy (<=44) format your 43.9 log shows."

log "Session type : $SESSION_TYPE"
log "GNOME Shell  : $(gnome-shell --version 2>/dev/null)"
log "Install path : $EXT_DIR"

# ---------------------------------------------------- enable-only mode (post-logout)
if [[ "${1:-}" == "--enable-only" ]]; then
    if have gsettings && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.shell'; then
        gsettings set org.gnome.shell disable-user-extensions false || true
    fi
    if enable_ext; then
        sleep 1
        is_active && finish_success
        [[ "$(ext_state)" == "ERROR" ]] && { show_journal_errors; die "Extension loaded with errors — see log lines above."; }
        finish_success
    fi
    die "Shell still says the extension does not exist. Log out/in first (Wayland) or Alt+F2 -> r (X11)."
fi

# ---------------------------------------------------------------- phase 1: clean slate
if [[ -e "$EXT_DIR" && ! -w "$EXT_DIR" ]]; then
    die "$EXT_DIR is not writable by you (left over from a sudo run?). Fix with: sudo rm -rf '$EXT_DIR' — then re-run."
fi

log "Removing previous install (keeping ~/.config/public-ip-flag/state.json if present)"
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR"

# ---------------------------------------------------------------- phase 2: write files
log "Writing clean extension files"

cat > "$EXT_DIR/metadata.json" << EOF
{
  "uuid": "$UUID",
  "name": "Public IP & Flag",
  "description": "Displays your public IP address with country flag emoji in the top panel. Left-click toggles hiding the IP (persistent); right-click refreshes.",
  "version": 1,
  "shell-version": ["$SHELL_MAJOR"]
}
EOF

cat > "$EXT_DIR/extension.js" << 'JS_EOF'
/* Public IP & Flag — GNOME Shell 43 compatible (legacy imports style)
 *
 * Left-click : toggle IP hidden / visible (persistent via state file)
 * Right-click: refresh now
 */

const {GObject, Gio, St, GLib, Clutter} = imports.gi;

const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const ByteArray = imports.byteArray;

// libsoup 3 (GNOME 43); guarded so a missing typelib falls back to curl/wget.
// Never load Soup 2.4 here — mixing soup2 into the soup3 shell crashes it.
let Soup = null;
try {
    imports.gi.versions.Soup = '3.0';
    Soup = imports.gi.Soup;
} catch (e) {
    Soup = null;
}

const API_URL = 'https://ipinfo.io/json';
const REFRESH_SECONDS = 300;
const MASKED_IP = '•••.•••.•••.•••';

const STATE_DIR = GLib.build_filenamev([GLib.get_user_config_dir(), 'public-ip-flag']);
const STATE_FILE = GLib.build_filenamev([STATE_DIR, 'state.json']);

function countryCodeToFlag(countryCode) {
    if (!countryCode || countryCode.length !== 2)
        return '🌐';
    const base = 0x1F1E6; // regional indicator symbol 'A'
    const cc = countryCode.toUpperCase();
    return String.fromCodePoint(
        cc.charCodeAt(0) - 65 + base,
        cc.charCodeAt(1) - 65 + base);
}

const PublicIpIndicator = GObject.registerClass(
class PublicIpIndicator extends PanelMenu.Button {
    _init() {
        // dontCreateMenu=true: we get a PopupDummyMenu whose toggle() is a
        // no-op, so clicks never open an empty popup. This is the shell's own
        // supported pattern for click-only panel buttons (same as Activities).
        super._init(0.0, 'Public IP & Flag', true);

        this._label = new St.Label({
            text: '🌐 …',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'public-ip-label',
        });
        this.add_child(this._label);

        this.leftClickCallback = null;   // toggle hidden
        this.rightClickCallback = null;  // refresh
        this.connect('button-press-event', (actor, event) => {
            const button = event.get_button();
            if (button === 1 && this.leftClickCallback)
                this.leftClickCallback();
            else if (button === 3 && this.rightClickCallback)
                this.rightClickCallback();
            return Clutter.EVENT_PROPAGATE;
        });
    }

    setText(text) {
        this._label.set_text(text);
    }
});

class Extension {
    constructor() {
        this._indicator = null;
        this._session = null;
        this._cancellable = null;
        this._timeoutId = 0;
        this._hidden = false;
        this._lastIp = null;
        this._lastCountry = null;
    }

    enable() {
        this._loadState();

        this._indicator = new PublicIpIndicator();
        this._indicator.leftClickCallback = () => this._toggleHidden();
        this._indicator.rightClickCallback = () => this._refresh();
        Main.panel.addToStatusArea('public-ip-flag', this._indicator, 1, 'right');

        this._cancellable = new Gio.Cancellable();
        if (Soup)
            this._session = new Soup.Session();

        this._refresh();
        this._timeoutId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    disable() {
        if (this._timeoutId) {
            GLib.Source.remove(this._timeoutId);
            this._timeoutId = 0;
        }
        if (this._cancellable) {
            this._cancellable.cancel();
            this._cancellable = null;
        }
        this._session = null;
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
        this._lastIp = null;
        this._lastCountry = null;
    }

    // ---- hidden / visible toggle, persisted to disk ----

    _toggleHidden() {
        this._hidden = !this._hidden;
        this._saveState();
        this._render();
    }

    _loadState() {
        try {
            const [, contents] = GLib.file_get_contents(STATE_FILE);
            const state = JSON.parse(ByteArray.toString(contents));
            this._hidden = state.hidden === true;
        } catch (e) {
            this._hidden = false; // no readable state file — default to visible
        }
    }

    _saveState() {
        try {
            GLib.mkdir_with_parents(STATE_DIR, 0o755);
            GLib.file_set_contents(STATE_FILE, JSON.stringify({hidden: this._hidden}));
        } catch (e) {
            log(`public-ip-flag: could not save state: ${e.message}`);
        }
    }

    _render() {
        if (!this._indicator)
            return;
        if (!this._lastIp) {
            this._indicator.setText('🌐 …');
            return;
        }
        const flag = countryCodeToFlag(this._lastCountry || '');
        const ipText = this._hidden ? MASKED_IP : this._lastIp;
        this._indicator.setText(`${flag} ${ipText}`);
    }

    // ---- fetching ----

    _refresh() {
        if (this._session)
            this._refreshWithSoup();
        else
            this._refreshWithSubprocess();
    }

    _refreshWithSoup() {
        const msg = Soup.Message.new('GET', API_URL);
        this._session.send_and_read_async(
            msg, GLib.PRIORITY_DEFAULT, this._cancellable,
            (session, result) => {
                try {
                    const bytes = session.send_and_read_finish(result);
                    if (msg.get_status() !== Soup.Status.OK)
                        throw new Error(`HTTP status ${msg.get_status()}`);
                    this._applyResponse(ByteArray.toString(bytes.get_data()));
                } catch (e) {
                    this._handleError(e);
                }
            });
    }

    _refreshWithSubprocess() {
        const curl = GLib.find_program_in_path('curl');
        const wget = GLib.find_program_in_path('wget');
        let argv = null;
        if (curl)
            argv = [curl, '-fsS', '--max-time', '10', API_URL];
        else if (wget)
            argv = [wget, '-q', '-O', '-', '-T', '10', API_URL];

        if (!argv) {
            if (this._indicator && !this._lastIp)
                this._indicator.setText('🌐 install curl or wget');
            return;
        }

        try {
            const proc = new Gio.Subprocess({
                argv,
                flags: Gio.SubprocessFlags.STDOUT_PIPE |
                       Gio.SubprocessFlags.STDERR_SILENCE,
            });
            proc.communicate_utf8_async(null, this._cancellable, (p, result) => {
                try {
                    const [, stdout] = p.communicate_utf8_finish(result);
                    this._applyResponse(stdout);
                } catch (e) {
                    this._handleError(e);
                }
            });
        } catch (e) {
            this._handleError(e);
        }
    }

    _applyResponse(text) {
        const data = JSON.parse(text);
        this._lastIp = data.ip || null;
        this._lastCountry = data.country || null;
        this._render();
    }

    _handleError(e) {
        // ignore requests cancelled while disabling
        if (e && e.matches &&
            e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
            return;
        log(`public-ip-flag: ${e.message}`);
        // keep showing the last known (possibly masked) IP on transient errors
        if (this._indicator && !this._lastIp)
            this._indicator.setText('🌐 unavailable');
    }
}

function init() {
    return new Extension();
}
JS_EOF

cat > "$EXT_DIR/stylesheet.css" << 'CSS_EOF'
.public-ip-label {
    padding: 0 8px;
    font-weight: 500;
}
CSS_EOF

chmod 755 "$EXT_BASE" "$EXT_DIR"
chmod 644 "$EXT_DIR/metadata.json" "$EXT_DIR/extension.js" "$EXT_DIR/stylesheet.css"
ok "Files written ($(wc -l < "$EXT_DIR/extension.js") lines of extension.js)."

# ---------------------------------------------------------------- phase 3: validate
if have python3; then
    python3 -m json.tool "$EXT_DIR/metadata.json" > /dev/null || die "metadata.json failed JSON validation."
fi
grep -q "\"uuid\": \"$UUID\"" "$EXT_DIR/metadata.json" || die "metadata uuid mismatch."
ok "Validation passed."

# ---------------------------------------------------------------- phase 4: extensions allowed globally?
if have gsettings && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.shell'; then
    if [[ "$(gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)" == "true" ]]; then
        warn "User extensions were globally DISABLED — re-enabling them."
        gsettings set org.gnome.shell disable-user-extensions false
    fi
fi

# ---------------------------------------------------------------- phase 5: activate
restart_shell_x11() {
    if have busctl && busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("Restarting…")' >/dev/null 2>&1; then
        return 0
    fi
    if have killall; then
        warn "D-Bus restart failed, trying SIGQUIT fallback (killall -3 gnome-shell)."
        killall -3 gnome-shell 2>/dev/null && return 0
    fi
    return 1
}

if shell_knows; then
    # ---------------- update path: shell already knows the uuid ----------------
    log "Extension is already registered with the running shell — this is an UPDATE."
    # make sure it is enabled (a previous run may have left it disabled)
    enable_ext || true
    sleep 1
    state="$(ext_state)"
    if [[ "$state" == "ERROR" ]]; then
        show_journal_errors
        die "Extension is in ERROR state — see log lines above."
    fi
    if [[ "$SESSION_TYPE" == "x11" ]]; then
        log "X11 session — restarting GNOME Shell in place to load the new code (screen may flicker)…"
        if restart_shell_x11; then
            for _ in 1 2 3 4 5 6 7 8; do
                sleep 2
                if is_active; then
                    finish_success
                fi
            done
        fi
        warn "Automatic restart didn't take. Press Alt+F2, type 'r', Enter."
        echo "    The extension is already enabled — it will come up with the new feature."
        exit 1
    else
        cat << MSG

OK: files updated; extension state: ${state:-unknown}.

NOTE: a running GNOME Shell keeps its cached copy of previously loaded
extension code (the 43.9 JS importer is cached per path for the lifetime of
the process — nothing can change that in-session), so whether you need one
more logout depends on what state this session was in:

  - LEFT-CLICK the IP in the top bar now.
      * IP toggles to bullets        -> DONE, nothing more to do.
      * Still just refreshes (old behavior), or nothing is visible
        -> log out and back in once. The extension is already enabled,
           so it loads the new code automatically at login.

MSG
        exit 0
    fi
fi

# ---------------- first-install path: shell has never seen the uuid ----------------
log "Attempt 1/3: enable directly (works if the shell already scanned the dir)"
if enable_ext; then
    sleep 1
    is_active && finish_success
fi

log "Attempt 2/3: ask the running shell to rescan extension dirs over D-Bus"
EVAL_RESCAN='(function(){try{var m=imports.ui.main;var em=m.extensionManager||m.extensionSystem;if(em&&typeof em._loadExtensions==="function"){em._loadExtensions();return "RESCANNED";}return "NO_MANAGER";}catch(e){return "ERR:"+e.message;}})()'
if have busctl; then
    if out="$(busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s "$EVAL_RESCAN" 2>&1)"; then
        log "Shell Eval replied: $out"
        sleep 1
        if enable_ext; then
            sleep 1
            is_active && finish_success
            [[ "$(ext_state)" == "ERROR" ]] && { show_journal_errors; die "Extension is in ERROR state — see log lines above."; }
        fi
    else
        warn "D-Bus Eval not available on this system."
    fi
else
    warn "busctl not found."
fi

if [[ "$SESSION_TYPE" == "x11" ]]; then
    log "Attempt 3/3: X11 session — restarting GNOME Shell in place (screen may flicker)"
    if restart_shell_x11; then
        for _ in 1 2 3 4 5 6 7 8; do
            sleep 2
            if enable_ext; then
                sleep 1
                is_active && finish_success
                [[ "$(ext_state)" == "ERROR" ]] && { show_journal_errors; die "Extension is in ERROR state — see log lines above."; }
                finish_success
            fi
        done
    fi
    warn "Shell restart did not make the extension visible."
    echo "    Do it manually: press Alt+F2, type 'r', press Enter, then run:"
    echo "        $0 --enable-only"
    exit 1
else
    cat << MSG

OK: Files are installed correctly, but the running GNOME Shell has not
picked up the new extension yet (session type: $SESSION_TYPE — on Wayland
only a fresh login scans new extension directories).

Finish the deploy:
  1. Save your work, LOG OUT, and log back in.
  2. Run:  $0 --enable-only
     (or:  gnome-extensions enable $UUID)

MSG
    exit 1
fi
