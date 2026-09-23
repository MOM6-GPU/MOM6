#!/usr/bin/env python3
"""Interactive terminal browser for GPU-port coverage.

Lets you navigate gcov execution counts overlaid with each line's
ported/portable/executed/not-hit status — the same four states as
track_gpu_port.py's HTML report (see LEGEND below), but for jumping around
a checkout interactively instead of reading a static page.

Reuses track_gpu_port.py's source-tree and gcov parsing directly (same
process, same module), so this can never disagree with the markdown/HTML/CI
report on what counts as "ported" or "portable" — it's just a different view
onto the same classification.

Requires the `textual` package (not a dependency of track_gpu_port.py
itself): `pip install textual`.

Usage:
    gpu_port_tui.py --src-root <dir> --gcov-dir <dir>

Keys: Enter opens the selected file; j/k or arrows move the cursor; n/N jump
to the next/previous portable-but-not-yet-ported line in the open file; Tab
switches between the file list and source view; q quits.
"""

import argparse
import sys
from pathlib import Path

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.widgets import DataTable, Footer, Header, Static

sys.path.insert(0, str(Path(__file__).parent))
import track_gpu_port as tgp  # noqa: E402

LEGEND = (
    "[white on #1b5e20] ported [/]  "
    "[white on #b71c1c] portable, not yet ported [/]  "
    "[white on #1565c0] executed, not portable [/]  "
    "[white on #555555] not hit [/]  "
    "[dim]nothing = not executable / no data[/]"
)

# Explicit hex, not named ANSI colors: Textual alpha-blends named colors (e.g. "blue")
# with a widget's background, which muddies them inside DataTable cells even though the
# same name renders true in the plain Static legend above.
STATE_STYLE = {
    'ported': 'white on #1b5e20',
    'portable': 'white on #b71c1c',
    'executed': 'white on #1565c0',
    'nothit': 'white on #555555',
    'nodata': '',
}


class GpuPortApp(App):
    """Browse gcov coverage overlaid with GPU-port status."""

    CSS = """
    #legend { height: 1; padding: 0 1; }
    Horizontal { height: 1fr; }
    #file-list { width: 56; border-right: solid $panel; }
    #source-view { width: 1fr; }
    """

    BINDINGS = [
        Binding('q', 'quit', 'Quit'),
        Binding('j', 'cursor_down', 'Down', show=False),
        Binding('k', 'cursor_up', 'Up', show=False),
        Binding('n', 'next_portable', 'Next portable'),
        Binding('N', 'prev_portable', 'Prev portable'),
    ]

    def __init__(self, src_root: Path, gcov_dir: Path):
        super().__init__()
        self.src_root = src_root
        self.gcov_dir = gcov_dir
        self.per_file = []       # summary rows, ranked like track_gpu_port's report
        self.fr_by_rel = {}      # rel path str -> FileRegions
        self.counts_by_rel = {}  # rel path str -> {line: count}
        self.resolved_by_rel = {}
        self.portable_lines = []  # sorted portable-line numbers for the open file

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(LEGEND, id='legend')
        with Horizontal():
            yield DataTable(id='file-list', cursor_type='row')
            yield DataTable(id='source-view', cursor_type='row')
        yield Footer()

    def on_mount(self) -> None:
        self.title = 'GPU port coverage'
        self.load_data()
        file_table = self.query_one('#file-list', DataTable)
        file_table.add_columns('File', 'Exec', 'Ported', 'Portable', '%')
        for r in self.per_file:
            pct = f"{r['pct_of_portable']:.0f}%" if r['pct_of_portable'] is not None else '—'
            file_table.add_row(r['file'], str(r['executed_lines']), str(r['ported_lines']),
                                str(r['portable_remaining_lines']), pct, key=r['file'])
        src_table = self.query_one('#source-view', DataTable)
        src_table.add_columns('Line', 'Cnt', 'Source')
        file_table.focus()
        if self.per_file:
            self.open_file(self.per_file[0]['file'])
        else:
            self.sub_title = f'no executed files found under {self.gcov_dir}'

    def load_data(self) -> None:
        """Mirror track_gpu_port.main()'s report-building loop, keeping per-file detail."""
        index = tgp.build_index(self.src_root)
        gcov_files = sorted(Path(self.gcov_dir).rglob('*.gcov'))
        exec_by_file = {}
        for gf in gcov_files:
            source, counts = tgp.parse_gcov(gf)
            if source is None or not counts:
                continue
            resolved = tgp.resolve_source(source, self.src_root, index)
            if resolved is None:
                continue
            merged = exec_by_file.setdefault(resolved, {})
            for ln, cnt in counts.items():
                merged[ln] = max(cnt, merged.get(ln, 0))

        empty_fr = tgp.FileRegions()
        per_file = []
        for resolved, counts in exec_by_file.items():
            executed = {ln for ln, c in counts.items() if c > 0}
            if not executed:
                continue
            try:
                fr = tgp.parse_ported_regions(resolved)
            except tgp.StructuralError:
                fr = empty_fr
            try:
                rel = str(resolved.relative_to(self.src_root))
            except ValueError:
                rel = str(resolved)
            executed_ported = executed & fr.ported
            executed_portable = (executed & fr.portable) - executed_ported
            portable_total = len(executed_ported) + len(executed_portable)
            per_file.append({
                'file': rel,
                'executed_lines': len(executed),
                'ported_lines': len(executed_ported),
                'portable_remaining_lines': len(executed_portable),
                'pct_of_portable': (100.0 * len(executed_ported) / portable_total
                                    if portable_total else None),
            })
            self.fr_by_rel[rel] = fr
            self.counts_by_rel[rel] = counts
            self.resolved_by_rel[rel] = resolved

        # Same ranking as the markdown/HTML report: biggest portable gap first.
        per_file.sort(key=lambda r: r['portable_remaining_lines'], reverse=True)
        self.per_file = per_file

    def open_file(self, rel: str) -> None:
        fr = self.fr_by_rel[rel]
        counts = self.counts_by_rel[rel]
        resolved = self.resolved_by_rel[rel]
        try:
            lines = resolved.read_text(errors='replace').splitlines()
        except OSError:
            lines = []
        src_table = self.query_one('#source-view', DataTable)
        src_table.clear()
        portable_lines = []
        for lineno, text in enumerate(lines, start=1):
            state, marker = tgp.classify_line(lineno, counts.get(lineno), fr)
            if state == 'portable':
                portable_lines.append(lineno)
            style = STATE_STYLE[state]
            src_table.add_row(
                Text(str(lineno), style=style, justify='right'),
                Text(marker, style=style, justify='right'),
                Text(text, style=style),
            )
        self.portable_lines = portable_lines
        self.sub_title = f'{rel} — {len(portable_lines)} portable line(s) not yet ported'

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        if event.data_table.id != 'file-list' or event.row_key.value is None:
            return
        self.open_file(str(event.row_key.value))
        self.query_one('#source-view', DataTable).focus()

    def action_cursor_down(self) -> None:
        widget = self.focused
        if isinstance(widget, DataTable):
            widget.action_cursor_down()

    def action_cursor_up(self) -> None:
        widget = self.focused
        if isinstance(widget, DataTable):
            widget.action_cursor_up()

    def action_next_portable(self) -> None:
        self._jump_portable(1)

    def action_prev_portable(self) -> None:
        self._jump_portable(-1)

    def _jump_portable(self, direction: int) -> None:
        if not self.portable_lines:
            return
        src_table = self.query_one('#source-view', DataTable)
        cur_line = (src_table.cursor_row or 0) + 1  # rows are 0-indexed, source lines aren't
        if direction > 0:
            target = next((ln for ln in self.portable_lines if ln > cur_line),
                           self.portable_lines[0])
        else:
            target = next((ln for ln in reversed(self.portable_lines) if ln < cur_line),
                           self.portable_lines[-1])
        src_table.move_cursor(row=target - 1)
        src_table.focus()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--src-root', required=True, help='Root of the source tree (same as track_gpu_port.py)')
    ap.add_argument('--gcov-dir', required=True, help='Directory containing .gcov files (recursively searched)')
    args = ap.parse_args()
    app = GpuPortApp(Path(args.src_root).resolve(), Path(args.gcov_dir).resolve())
    app.run()


if __name__ == '__main__':
    main()
