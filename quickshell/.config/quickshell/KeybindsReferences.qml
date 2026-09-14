pragma Singleton
import QtQuick

// Versioned, intentionally static shortcut references. Update these snapshots
// only alongside their version/source notes in docs/keybindings.md.
QtObject {
  id: root

  function records(category, text) {
    return text.trim().split("\n").filter(line => line !== "").map(line => {
      const parts = line.split("|")
      return { category: category, shortcut: parts[0], description: parts[1],
               detail: parts[2] || "", dispatcher: "reference", arg: "",
               mouse: false, actionable: false,
               searchText: (category + " " + parts.join(" ")).toLowerCase() }
    })
  }

  function lazyvim() {
    // LazyVim v16.0.1 baseline defaults. Leader is Space; localleader is \\.
    return [
      ...records("General", `j|Down|Normal, Visual
<Down>|Down|Normal, Visual
k|Up|Normal, Visual
<Up>|Up|Normal, Visual
Ctrl+h|Go to left window|Normal
Ctrl+j|Go to lower window|Normal
Ctrl+k|Go to upper window|Normal
Ctrl+l|Go to right window|Normal
Alt+j|Move down|Normal, Insert, Visual
Alt+k|Move up|Normal, Insert, Visual
Shift+h|Previous buffer|Normal
Shift+l|Next buffer|Normal
[ b|Previous buffer|Normal
] b|Next buffer|Normal
Space b b|Switch to other buffer|Normal
Space b d|Delete buffer|Normal
Space b o|Delete other buffers|Normal
Space b i|Delete invisible buffers|Normal
Esc|Escape and clear search highlight|Insert, Normal, Select
Ctrl+s|Save file|Insert, Visual, Normal, Select
Space c f|Format|Normal, Visual
Space c d|Line diagnostics|Normal
] d|Next diagnostic|Normal
[ d|Previous diagnostic|Normal
] e|Next error|Normal
[ e|Previous error|Normal
] w|Next warning|Normal
[ w|Previous warning|Normal
Space u f|Toggle auto format (global)|Normal
Space u F|Toggle auto format (buffer)|Normal
Space u s|Toggle spelling|Normal
Space u w|Toggle wrap|Normal
Space u L|Toggle relative number|Normal
Space u d|Toggle diagnostics|Normal
Space u l|Toggle line numbers|Normal
Space u c|Toggle conceal level|Normal
Space u A|Toggle tabline|Normal
Space u T|Toggle Treesitter highlight|Normal
Space u b|Toggle dark background|Normal
Space u D|Toggle dimming|Normal
Space u a|Toggle animations|Normal
Space u g|Toggle indent guides|Normal
Space u S|Toggle smooth scroll|Normal
Space u h|Toggle inlay hints|Normal
Space q q|Quit all|Normal
Space l|Lazy plugin manager|Normal
Space L|LazyVim changelog|Normal
Space f n|New file|Normal
Space f t|Terminal (root)|Normal
Space f T|Terminal (cwd)|Normal
Ctrl+/|Terminal (root)|Normal, Terminal
Space -|Split window below|Normal
Space | |Split window right|Normal
Space w d|Delete window|Normal
Space w m|Toggle zoom mode|Normal
Space u z|Toggle Zen mode|Normal
Space Tab Tab|New tab|Normal
Space Tab [|Previous tab|Normal
Space Tab ]|Next tab|Normal
Space Tab d|Close tab|Normal`),
      ...records("LSP", `g d|Go to definition|Normal
g r|References|Normal
g I|Go to implementation|Normal
g y|Go to type definition|Normal
g D|Go to declaration|Normal
K|Hover|Normal
g K|Signature help|Normal
Ctrl+k|Signature help|Insert
Space c a|Code action|Normal, Visual
Space c c|Run codelens|Normal, Visual
Space c C|Refresh codelens|Normal
Space c R|Rename file|Normal
Space c r|Rename symbol|Normal
Space c A|Source action|Normal
Space c o|Organize imports|Normal
] ]|Next reference|Normal
[ [|Previous reference|Normal
Alt+n|Next reference|Normal
Alt+p|Previous reference|Normal
Space s s|LSP symbols|Normal
Space s S|Workspace symbols|Normal`),
      ...records("Search and files", `Space Space|Find files (root)|Normal
Space ,|Buffers|Normal
Space /|Grep (root)|Normal
Space :|Command history|Normal
Space e|Explorer (root)|Normal
Space E|Explorer (cwd)|Normal
Space f b|Buffers|Normal
Space f B|All buffers|Normal
Space f c|Find config file|Normal
Space f f|Find files (root)|Normal
Space f F|Find files (cwd)|Normal
Space f g|Find git files|Normal
Space f p|Projects|Normal
Space f r|Recent files|Normal
Space s /|Search history|Normal
Space s a|Autocommands|Normal
Space s b|Buffer lines|Normal
Space s B|Grep open buffers|Normal
Space s c|Command history|Normal
Space s C|Commands|Normal
Space s d|Diagnostics|Normal
Space s D|Buffer diagnostics|Normal
Space s g|Grep (root)|Normal
Space s G|Grep (cwd)|Normal
Space s h|Help pages|Normal
Space s H|Highlights|Normal
Space s i|Icons|Normal
Space s j|Jumps|Normal
Space s k|Keymaps|Normal
Space s l|Location list|Normal
Space s m|Marks|Normal
Space s M|Man pages|Normal
Space s q|Quickfix list|Normal
Space s R|Resume picker|Normal
Space s u|Undotree|Normal
Space s w|Selection or word (root)|Normal, Visual
Space s W|Selection or word (cwd)|Normal, Visual`),
      ...records("Git and buffers", `Space g b|Git blame line|Normal
Space g f|Git current file history|Normal
Space g l|Git log|Normal
Space g L|Git log (cwd)|Normal
Space g B|Git browse (open)|Normal, Visual
Space g Y|Git browse (copy)|Normal, Visual
Space g d|Git diff hunks|Normal
Space g D|Git diff origin|Normal
Space g i|GitHub issues (open)|Normal
Space g I|GitHub issues (all)|Normal
Space g p|GitHub pull requests (open)|Normal
Space g P|GitHub pull requests (all)|Normal
Space g s|Git status|Normal
Space g S|Git stash|Normal
Space b j|Pick buffer|Normal
Space b l|Delete buffers to left|Normal
Space b p|Toggle buffer pin|Normal
Space b P|Delete non-pinned buffers|Normal
Space b r|Delete buffers to right|Normal
[ B|Move buffer previous|Normal
] B|Move buffer next|Normal`),
      ...records("Plugins", `Space c F|Format injected languages|Normal, Visual
Ctrl+s|Toggle Flash search|Command
r|Remote Flash|Operator-pending
R|Treesitter Flash|Operator-pending, Visual
s|Flash|Normal, Operator-pending, Visual
S|Flash Treesitter|Normal, Operator-pending, Visual
Space s r|Search and replace|Normal, Visual
Space c m|Mason|Normal
Ctrl+b|Scroll backward (Noice)|Normal, Insert, Select
Ctrl+f|Scroll forward (Noice)|Normal, Insert, Select
Space s n a|Noice all|Normal
Space s n d|Dismiss all Noice messages|Normal
Space s n h|Noice history|Normal
Space s n l|Noice last message|Normal
Space s n t|Noice picker|Normal
Shift+Enter|Redirect command line|Command
Space q d|Do not save current session|Normal
Space q l|Restore last session|Normal
Space q s|Restore session|Normal
Space q S|Select session|Normal
Space s t|Todo picker|Normal
Space s T|Todo/Fix/Fixme picker|Normal
Space x t|Todo Trouble|Normal
Space x T|Todo/Fix/Fixme Trouble|Normal
[ t|Previous todo comment|Normal
] t|Next todo comment|Normal
Space c s|Symbols (Trouble)|Normal
Space c S|LSP references/definitions (Trouble)|Normal
Space x L|Location list (Trouble)|Normal
Space x Q|Quickfix list (Trouble)|Normal
Space x x|Diagnostics (Trouble)|Normal
Space x X|Buffer diagnostics (Trouble)|Normal
Ctrl+w Space|Window Hydra mode|Normal
Space ?|Buffer keymaps|Normal`)
    ]
  }

  function herdr() {
    return [
      ...records("Session and workspaces", `Ctrl+b then ?|Open keybinding help|Prefix
Ctrl+b then s|Open settings|Prefix
Ctrl+b then q|Detach client|Prefix
Ctrl+b then Shift+r|Reload configuration|Prefix
Ctrl+b then o|Open notification target|Prefix
Ctrl+b then w|Workspace picker|Prefix
Ctrl+b then g|Goto picker|Prefix
Ctrl+b then Shift+n|New workspace|Prefix
Ctrl+b then Shift+g|New worktree|Prefix
Ctrl+b then Shift+w|Rename workspace|Prefix
Ctrl+b then Shift+d|Close workspace|Prefix`),
      ...records("Tabs", `Ctrl+b then c|New tab|Prefix
Ctrl+b then Shift+t|Rename tab|Prefix
Ctrl+b then p|Previous tab|Prefix
Ctrl+b then n|Next tab|Prefix
Ctrl+b then 1…9|Switch tab|Prefix
Ctrl+b then Shift+x|Close tab|Prefix`),
      ...records("Panes", `Ctrl+b then Shift+p|Rename pane|Prefix
Ctrl+b then e|Edit scrollback|Prefix
Ctrl+b then h|Focus pane left|Prefix
Ctrl+b then j|Focus pane down|Prefix
Ctrl+b then k|Focus pane up|Prefix
Ctrl+b then l|Focus pane right|Prefix
Ctrl+b then Tab|Next pane|Prefix
Ctrl+b then Shift+Tab|Previous pane|Prefix
Ctrl+b then v|Split vertically|Prefix
Ctrl+b then -|Split horizontally|Prefix
Ctrl+b then x|Close pane|Prefix
Ctrl+b then z|Toggle pane zoom|Prefix
Ctrl+b then r|Resize mode|Prefix
Ctrl+b then b|Toggle sidebar|Prefix`),
      ...records("Navigate mode", `Up|Workspace up|Navigate mode
Down|Workspace down|Navigate mode
h|Focus pane left|Navigate mode
j|Focus pane down|Navigate mode
k|Focus pane up|Navigate mode
l|Focus pane right|Navigate mode`),
      ...records("Remote", `Ctrl+v|Paste clipboard image|Remote sessions only`)
    ]
  }

  function rows(kind) {
    if (kind === "lazyvim") return lazyvim()
    if (kind === "herdr") return herdr()
    return []
  }
}
