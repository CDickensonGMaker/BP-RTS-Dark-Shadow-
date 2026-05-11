#!/usr/bin/env python3
"""
Code Auditor Daemon - Overnight Codebase Health Scanner

Scans the entire project for:
1. Orphaned/unused functions
2. Unused variables and constants
3. Disconnected signals (emitted but never connected, or vice versa)
4. Orphaned scene nodes (referenced but missing, or present but unreferenced)
5. Dead imports/preloads
6. Empty functions
7. TODO/FIXME/HACK comments
8. Duplicate code patterns
9. Inconsistent naming
10. Missing type hints

Outputs a comprehensive JSON report with proposed cleanups.

Usage:
    python code_auditor.py --output audit_report.json
    python code_auditor.py --hours 8  # Run overnight with full analysis
"""

import argparse
import json
import os
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any

# =============================================================================
# CONFIGURATION
# =============================================================================

PROJECT_PATH = Path(r"C:\Users\caleb\BP_RTS_Dark_Shadows")
AGENT_DIR = PROJECT_PATH / "tools" / "agent"

# Directories to scan
SCAN_DIRS = [
    "battle_system",
    "campaign_system",
    "scenes",
    "tools/agent",
]

# Directories/files to skip
SKIP_PATTERNS = [
    "__pycache__",
    ".git",
    ".import",
    "*.import",
    "*.uid",
    "addons",
]

# =============================================================================
# AUDITOR CLASS
# =============================================================================

class CodeAuditor:
    """Scans GDScript codebase for orphaned code and issues."""

    def __init__(self, project_path: Path):
        self.project_path = project_path
        self.findings: List[Dict] = []
        self.stats: Dict[str, int] = defaultdict(int)

        # Collected data
        self.all_functions: Dict[str, List[str]] = {}  # file -> [func names]
        self.all_signals: Dict[str, List[str]] = {}     # file -> [signal names]
        self.all_variables: Dict[str, List[str]] = {}   # file -> [var names]
        self.all_constants: Dict[str, List[str]] = {}   # file -> [const names]
        self.all_classes: Dict[str, str] = {}           # class_name -> file
        self.all_preloads: Dict[str, List[str]] = {}    # file -> [preloaded paths]

        # Cross-reference data
        self.function_calls: Dict[str, Set[str]] = defaultdict(set)  # func -> files that call it
        self.signal_emits: Dict[str, Set[str]] = defaultdict(set)    # signal -> files that emit it
        self.signal_connects: Dict[str, Set[str]] = defaultdict(set) # signal -> files that connect it
        self.class_usages: Dict[str, Set[str]] = defaultdict(set)    # class -> files that use it

        # Scene data
        self.scene_nodes: Dict[str, List[Dict]] = {}    # scene file -> [node dicts]
        self.scene_scripts: Dict[str, str] = {}          # scene file -> attached script

    def log(self, msg: str, level: str = "info"):
        """Print log message."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        prefix = {"info": "[*]", "warn": "[!]", "error": "[X]", "ok": "[+]"}.get(level, "[*]")
        print(f"[{timestamp}] {prefix} {msg}")

    def add_finding(self, category: str, severity: str, title: str,
                    file_path: str, line: int = 0, details: Dict = None,
                    proposed_action: str = ""):
        """Add an audit finding."""
        finding = {
            "category": category,
            "severity": severity,
            "title": title,
            "file": file_path,
            "line": line,
            "details": details or {},
            "proposed_action": proposed_action,
        }
        self.findings.append(finding)
        self.stats[f"{category}_{severity}"] += 1

    # =========================================================================
    # FILE COLLECTION
    # =========================================================================

    def collect_files(self) -> Tuple[List[Path], List[Path]]:
        """Collect all GDScript and scene files."""
        gd_files = []
        tscn_files = []

        for scan_dir in SCAN_DIRS:
            dir_path = self.project_path / scan_dir
            if not dir_path.exists():
                continue

            for file_path in dir_path.rglob("*"):
                # Skip patterns
                skip = False
                for pattern in SKIP_PATTERNS:
                    if pattern.startswith("*"):
                        if file_path.name.endswith(pattern[1:]):
                            skip = True
                            break
                    elif pattern in str(file_path):
                        skip = True
                        break
                if skip:
                    continue

                if file_path.suffix == ".gd":
                    gd_files.append(file_path)
                elif file_path.suffix == ".tscn":
                    tscn_files.append(file_path)

        self.log(f"Found {len(gd_files)} GDScript files, {len(tscn_files)} scene files")
        return gd_files, tscn_files

    # =========================================================================
    # GDSCRIPT PARSING
    # =========================================================================

    def parse_gdscript(self, file_path: Path) -> Dict:
        """Parse a GDScript file and extract definitions."""
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            self.log(f"Error reading {file_path}: {e}", "error")
            return {}

        rel_path = str(file_path.relative_to(self.project_path))
        lines = content.split('\n')

        result = {
            "functions": [],
            "signals": [],
            "variables": [],
            "constants": [],
            "class_name": None,
            "extends": None,
            "preloads": [],
            "todos": [],
            "empty_funcs": [],
        }

        # Patterns
        func_pattern = re.compile(r'^func\s+(\w+)\s*\(')
        signal_pattern = re.compile(r'^signal\s+(\w+)')
        var_pattern = re.compile(r'^(?:@export\s+)?var\s+(\w+)')
        const_pattern = re.compile(r'^const\s+(\w+)')
        class_pattern = re.compile(r'^class_name\s+(\w+)')
        extends_pattern = re.compile(r'^extends\s+(\w+)')
        preload_pattern = re.compile(r'preload\s*\(\s*["\']([^"\']+)["\']\s*\)')
        load_pattern = re.compile(r'(?<!pre)load\s*\(\s*["\']([^"\']+)["\']\s*\)')
        todo_pattern = re.compile(r'#\s*(TODO|FIXME|HACK|XXX|BUG)[\s:]+(.+)', re.IGNORECASE)

        current_func = None
        func_start_line = 0
        func_has_code = False

        for i, line in enumerate(lines):
            stripped = line.strip()

            # Track function bodies for empty function detection
            if current_func:
                if stripped and not stripped.startswith('#') and not stripped.startswith('pass'):
                    if not line.startswith('\t') and not line.startswith(' '):
                        # New top-level definition, function ended
                        if not func_has_code:
                            result["empty_funcs"].append((current_func, func_start_line))
                        current_func = None
                    else:
                        func_has_code = True
                elif stripped == 'pass':
                    pass  # Just a pass statement

            # Function definitions
            match = func_pattern.match(stripped)
            if match:
                func_name = match.group(1)
                result["functions"].append((func_name, i + 1))
                current_func = func_name
                func_start_line = i + 1
                func_has_code = False

            # Signals
            match = signal_pattern.match(stripped)
            if match:
                result["signals"].append((match.group(1), i + 1))

            # Variables
            match = var_pattern.match(stripped)
            if match:
                result["variables"].append((match.group(1), i + 1))

            # Constants
            match = const_pattern.match(stripped)
            if match:
                result["constants"].append((match.group(1), i + 1))

            # Class name
            match = class_pattern.match(stripped)
            if match:
                result["class_name"] = match.group(1)

            # Extends
            match = extends_pattern.match(stripped)
            if match:
                result["extends"] = match.group(1)

            # Preloads
            for match in preload_pattern.finditer(line):
                result["preloads"].append((match.group(1), i + 1))
            for match in load_pattern.finditer(line):
                result["preloads"].append((match.group(1), i + 1))

            # TODOs
            match = todo_pattern.search(line)
            if match:
                result["todos"].append((match.group(1), match.group(2).strip(), i + 1))

        # Store in class data
        self.all_functions[rel_path] = [f[0] for f in result["functions"]]
        self.all_signals[rel_path] = [s[0] for s in result["signals"]]
        self.all_variables[rel_path] = [v[0] for v in result["variables"]]
        self.all_constants[rel_path] = [c[0] for c in result["constants"]]
        if result["class_name"]:
            self.all_classes[result["class_name"]] = rel_path
        self.all_preloads[rel_path] = [p[0] for p in result["preloads"]]

        return result

    def analyze_gdscript_usage(self, file_path: Path, content: str):
        """Analyze a GDScript file for function calls, signal usage, etc."""
        rel_path = str(file_path.relative_to(self.project_path))

        # Find function calls
        call_pattern = re.compile(r'\.(\w+)\s*\(|(?<![.\w])(\w+)\s*\(')
        for match in call_pattern.finditer(content):
            func_name = match.group(1) or match.group(2)
            if func_name and not func_name.startswith('_'):  # Skip builtins
                self.function_calls[func_name].add(rel_path)

        # Find signal emits
        emit_pattern = re.compile(r'(\w+)\.emit\(|emit_signal\s*\(\s*["\'](\w+)["\']')
        for match in emit_pattern.finditer(content):
            signal_name = match.group(1) or match.group(2)
            if signal_name:
                self.signal_emits[signal_name].add(rel_path)

        # Find signal connects
        connect_pattern = re.compile(r'(\w+)\.connect\(|connect\s*\(\s*["\'](\w+)["\']')
        for match in connect_pattern.finditer(content):
            signal_name = match.group(1) or match.group(2)
            if signal_name:
                self.signal_connects[signal_name].add(rel_path)

        # Find class usages
        for class_name in self.all_classes.keys():
            if re.search(rf'\b{class_name}\b', content):
                self.class_usages[class_name].add(rel_path)

    # =========================================================================
    # SCENE PARSING
    # =========================================================================

    def parse_scene(self, file_path: Path) -> Dict:
        """Parse a .tscn scene file."""
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            self.log(f"Error reading {file_path}: {e}", "error")
            return {}

        rel_path = str(file_path.relative_to(self.project_path))

        result = {
            "nodes": [],
            "scripts": [],
            "resources": [],
            "external_resources": [],
        }

        # Parse external resources
        ext_res_pattern = re.compile(r'\[ext_resource\s+.*?path="([^"]+)".*?\]')
        for match in ext_res_pattern.finditer(content):
            result["external_resources"].append(match.group(1))

        # Parse nodes
        node_pattern = re.compile(r'\[node\s+name="([^"]+)".*?\]')
        for match in node_pattern.finditer(content):
            result["nodes"].append(match.group(1))

        # Find attached scripts
        script_pattern = re.compile(r'script\s*=\s*ExtResource\s*\(\s*"([^"]+)"')
        for match in script_pattern.finditer(content):
            result["scripts"].append(match.group(1))

        self.scene_nodes[rel_path] = result["nodes"]

        return result

    # =========================================================================
    # AUDIT CHECKS
    # =========================================================================

    def check_unused_functions(self, gd_files: List[Path]):
        """Find functions that are never called."""
        self.log("Checking for unused functions...")

        # Collect all content for cross-reference
        all_content = {}
        for file_path in gd_files:
            try:
                all_content[file_path] = file_path.read_text(encoding='utf-8', errors='ignore')
            except:
                pass

        # Check each function
        for file_path, funcs in self.all_functions.items():
            full_path = self.project_path / file_path
            if full_path not in all_content:
                continue

            for func_name in funcs:
                # Skip special functions
                if func_name.startswith('_') and func_name in [
                    '_init', '_ready', '_process', '_physics_process',
                    '_enter_tree', '_exit_tree', '_input', '_unhandled_input',
                    '_notification', '_get_configuration_warnings', '_draw'
                ]:
                    continue

                # Skip signal callbacks (common pattern: _on_*)
                if func_name.startswith('_on_'):
                    continue

                # Check if called anywhere
                call_count = 0
                for other_path, other_content in all_content.items():
                    # Look for function calls (not definitions)
                    pattern = rf'(?<!func\s){func_name}\s*\('
                    if re.search(pattern, other_content):
                        call_count += 1

                # If only defined but never called (count=1 means only the definition)
                if call_count <= 1 and not func_name.startswith('_'):
                    self.add_finding(
                        category="unused_function",
                        severity="low",
                        title=f"Unused function: {func_name}",
                        file_path=file_path,
                        details={"function": func_name},
                        proposed_action=f"Consider removing {func_name}() if truly unused"
                    )

    def check_unused_signals(self):
        """Find signals that are defined but never emitted or connected."""
        self.log("Checking for unused signals...")

        for file_path, signals in self.all_signals.items():
            if not signals:
                continue
            for item in signals:
                if isinstance(item, tuple):
                    sig = item[0]
                else:
                    sig = item

                emitted = sig in self.signal_emits and len(self.signal_emits[sig]) > 0
                connected = sig in self.signal_connects and len(self.signal_connects[sig]) > 0

                if not emitted and not connected:
                    self.add_finding(
                        category="unused_signal",
                        severity="low",
                        title=f"Unused signal: {sig}",
                        file_path=file_path,
                        details={"signal": sig, "emitted": emitted, "connected": connected},
                        proposed_action=f"Remove signal '{sig}' if no longer needed"
                    )
                elif emitted and not connected:
                    self.add_finding(
                        category="orphan_signal",
                        severity="medium",
                        title=f"Signal emitted but never connected: {sig}",
                        file_path=file_path,
                        details={"signal": sig, "emitters": list(self.signal_emits.get(sig, []))},
                        proposed_action=f"Connect signal '{sig}' or remove emit calls"
                    )

    def check_orphan_preloads(self, gd_files: List[Path]):
        """Find preloads/loads that reference non-existent files."""
        self.log("Checking for orphan preloads...")

        for file_path, preloads in self.all_preloads.items():
            for preload_path in preloads:
                # Convert res:// path to actual path
                if preload_path.startswith("res://"):
                    actual_path = self.project_path / preload_path[6:]
                else:
                    actual_path = self.project_path / preload_path

                if not actual_path.exists():
                    self.add_finding(
                        category="orphan_preload",
                        severity="high",
                        title=f"Missing preload: {preload_path}",
                        file_path=file_path,
                        details={"preload_path": preload_path},
                        proposed_action=f"Remove or fix reference to {preload_path}"
                    )

    def check_empty_functions(self, parse_results: Dict[str, Dict]):
        """Find functions with no implementation (just pass or empty)."""
        self.log("Checking for empty functions...")

        for file_path, result in parse_results.items():
            for func_name, line in result.get("empty_funcs", []):
                # Skip intentionally empty callbacks
                if func_name.startswith('_on_') or func_name in ['_ready', '_process']:
                    continue

                self.add_finding(
                    category="empty_function",
                    severity="low",
                    title=f"Empty function: {func_name}",
                    file_path=file_path,
                    line=line,
                    details={"function": func_name},
                    proposed_action=f"Implement or remove {func_name}()"
                )

    def check_todos(self, parse_results: Dict[str, Dict]):
        """Collect all TODO/FIXME/HACK comments."""
        self.log("Collecting TODO/FIXME/HACK comments...")

        for file_path, result in parse_results.items():
            for todo_type, todo_text, line in result.get("todos", []):
                severity = "medium" if todo_type.upper() in ["FIXME", "BUG", "HACK"] else "low"
                self.add_finding(
                    category="todo",
                    severity=severity,
                    title=f"{todo_type.upper()}: {todo_text[:60]}",
                    file_path=file_path,
                    line=line,
                    details={"type": todo_type, "text": todo_text},
                    proposed_action=f"Address {todo_type}: {todo_text[:40]}..."
                )

    def check_unused_classes(self):
        """Find class_name definitions that are never used."""
        self.log("Checking for unused classes...")

        for class_name, file_path in self.all_classes.items():
            if class_name not in self.class_usages or len(self.class_usages[class_name]) <= 1:
                self.add_finding(
                    category="unused_class",
                    severity="low",
                    title=f"Unused class_name: {class_name}",
                    file_path=file_path,
                    details={"class_name": class_name},
                    proposed_action=f"Remove class_name '{class_name}' if only used locally"
                )

    def check_scene_script_references(self, tscn_files: List[Path]):
        """Check that scripts referenced in scenes exist."""
        self.log("Checking scene script references...")

        for scene_path in tscn_files:
            try:
                content = scene_path.read_text(encoding='utf-8', errors='ignore')
            except:
                continue

            rel_path = str(scene_path.relative_to(self.project_path))

            # Find script references
            script_pattern = re.compile(r'path="(res://[^"]+\.gd)"')
            for match in script_pattern.finditer(content):
                script_path = match.group(1)
                actual_path = self.project_path / script_path[6:]

                if not actual_path.exists():
                    self.add_finding(
                        category="missing_script",
                        severity="high",
                        title=f"Scene references missing script: {script_path}",
                        file_path=rel_path,
                        details={"script_path": script_path},
                        proposed_action=f"Fix or remove reference to {script_path}"
                    )

    def check_duplicate_functions(self, gd_files: List[Path]):
        """Find functions with identical or very similar implementations."""
        self.log("Checking for duplicate functions...")

        # Collect function bodies
        func_bodies: Dict[str, List[Tuple[str, str, int]]] = defaultdict(list)

        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
            except:
                continue

            rel_path = str(file_path.relative_to(self.project_path))

            # Simple regex to extract function bodies
            func_pattern = re.compile(r'^func\s+(\w+)\s*\([^)]*\)[^:]*:(.*?)(?=^func\s|\Z)', re.MULTILINE | re.DOTALL)
            for match in func_pattern.finditer(content):
                func_name = match.group(1)
                body = match.group(2).strip()

                # Skip very short functions
                if len(body) < 50:
                    continue

                # Normalize body (remove whitespace variations)
                normalized = re.sub(r'\s+', ' ', body)
                func_bodies[normalized].append((func_name, rel_path, match.start()))

        # Find duplicates
        for body_hash, locations in func_bodies.items():
            if len(locations) > 1:
                names = [f"{loc[0]} in {loc[1]}" for loc in locations[:3]]
                self.add_finding(
                    category="duplicate_function",
                    severity="medium",
                    title=f"Duplicate function implementations found",
                    file_path=locations[0][1],
                    details={
                        "count": len(locations),
                        "locations": names,
                        "body_preview": body_hash[:100]
                    },
                    proposed_action="Consider extracting to a shared utility function"
                )

    def check_large_files(self, gd_files: List[Path]):
        """Flag files that are too large."""
        self.log("Checking for large files...")

        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
                lines = len(content.split('\n'))
            except:
                continue

            rel_path = str(file_path.relative_to(self.project_path))

            if lines > 1000:
                self.add_finding(
                    category="large_file",
                    severity="medium" if lines > 2000 else "low",
                    title=f"Large file: {lines} lines",
                    file_path=rel_path,
                    details={"lines": lines},
                    proposed_action="Consider splitting into smaller modules"
                )

    # =========================================================================
    # OPTIMIZATION CHECKS
    # =========================================================================

    def check_performance_issues(self, gd_files: List[Path]):
        """Find common performance anti-patterns."""
        self.log("Checking for performance issues...")

        perf_patterns = [
            # Pattern: (regex, severity, title, proposed_action)
            (r'get_node\s*\([^)]+\)', "medium", "get_node() in hot path",
             "Cache node references in _ready() instead of repeated get_node() calls"),
            (r'find_child\s*\(', "medium", "find_child() call",
             "Cache child references or use @onready instead of runtime search"),
            (r'get_tree\(\)\.get_nodes_in_group\s*\(', "low", "get_nodes_in_group() call",
             "Consider caching group results if called frequently"),
            (r'\.duplicate\s*\(', "low", "Object duplication",
             "Verify duplicate() is necessary - consider object pooling"),
            (r'for\s+\w+\s+in\s+range\s*\(\s*\d{4,}', "high", "Large loop with range()",
             "Loop over 1000+ iterations may cause frame drops"),
            (r'await\s+get_tree\(\)\.create_timer', "low", "Timer in function",
             "Consider using Timer node for repeated delays"),
            (r'\.instance\(\)|\.instantiate\(\)', "low", "Scene instantiation",
             "Consider object pooling for frequently spawned objects"),
            (r'ResourceLoader\.load\s*\(', "medium", "Runtime resource loading",
             "Preload resources at startup when possible"),
            (r'str\s*\([^)]+\)\s*\+\s*str\s*\(', "low", "String concatenation in loop",
             "Use string formatting or StringName for repeated concatenation"),
            (r'\.size\(\)\s*(?:>|<|==|!=)\s*0', "low", "size() comparison",
             "Use is_empty() instead of size() == 0 for better performance"),
        ]

        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
            except:
                continue

            rel_path = str(file_path.relative_to(self.project_path))
            lines = content.split('\n')

            # Check if this is a _process or _physics_process context
            in_process_func = False

            for i, line in enumerate(lines):
                stripped = line.strip()

                # Track if we're in a process function
                if re.match(r'^func\s+_(?:physics_)?process', stripped):
                    in_process_func = True
                elif stripped.startswith('func '):
                    in_process_func = False

                for pattern, severity, title, action in perf_patterns:
                    if re.search(pattern, line):
                        # Upgrade severity if in process function
                        actual_severity = severity
                        if in_process_func and severity == "low":
                            actual_severity = "medium"
                        elif in_process_func and severity == "medium":
                            actual_severity = "high"

                        self.add_finding(
                            category="performance",
                            severity=actual_severity,
                            title=f"{title}" + (" (in _process)" if in_process_func else ""),
                            file_path=rel_path,
                            line=i + 1,
                            details={"pattern": pattern, "in_process": in_process_func},
                            proposed_action=action
                        )

    def check_spaghetti_code(self, gd_files: List[Path]):
        """Detect spaghetti code patterns and complexity issues."""
        self.log("Checking for spaghetti code patterns...")

        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
            except:
                continue

            rel_path = str(file_path.relative_to(self.project_path))
            lines = content.split('\n')

            # Track function metrics
            current_func = None
            func_start = 0
            func_lines = 0
            max_indent = 0
            branch_count = 0  # if/elif/match
            nested_loops = 0

            for i, line in enumerate(lines):
                stripped = line.strip()

                # New function
                if re.match(r'^func\s+(\w+)', stripped):
                    # Report previous function if it was complex
                    if current_func:
                        self._report_function_complexity(
                            rel_path, current_func, func_start,
                            func_lines, max_indent, branch_count, nested_loops
                        )

                    match = re.match(r'^func\s+(\w+)', stripped)
                    current_func = match.group(1)
                    func_start = i + 1
                    func_lines = 0
                    max_indent = 0
                    branch_count = 0
                    nested_loops = 0
                elif current_func:
                    # Count function metrics
                    func_lines += 1

                    # Count indentation level
                    indent = len(line) - len(line.lstrip('\t'))
                    max_indent = max(max_indent, indent)

                    # Count branches
                    if re.match(r'\s*(if|elif|match|case)\s', line):
                        branch_count += 1

                    # Count nested loops
                    if re.match(r'\s*(for|while)\s', line) and indent > 1:
                        nested_loops += 1

            # Don't forget last function
            if current_func:
                self._report_function_complexity(
                    rel_path, current_func, func_start,
                    func_lines, max_indent, branch_count, nested_loops
                )

            # Check file-level issues
            self._check_file_spaghetti(rel_path, content, lines)

    def _report_function_complexity(self, file_path: str, func_name: str,
                                     line: int, func_lines: int, max_indent: int,
                                     branch_count: int, nested_loops: int):
        """Report complexity issues for a function."""

        # Long function
        if func_lines > 100:
            self.add_finding(
                category="spaghetti",
                severity="high" if func_lines > 200 else "medium",
                title=f"Long function: {func_name}() is {func_lines} lines",
                file_path=file_path,
                line=line,
                details={"function": func_name, "lines": func_lines},
                proposed_action="Split into smaller, focused functions"
            )

        # Deep nesting
        if max_indent >= 5:
            self.add_finding(
                category="spaghetti",
                severity="high" if max_indent >= 7 else "medium",
                title=f"Deep nesting: {func_name}() has {max_indent} indent levels",
                file_path=file_path,
                line=line,
                details={"function": func_name, "max_indent": max_indent},
                proposed_action="Use early returns or extract nested logic to helper functions"
            )

        # High cyclomatic complexity (many branches)
        if branch_count > 10:
            self.add_finding(
                category="spaghetti",
                severity="high" if branch_count > 15 else "medium",
                title=f"High complexity: {func_name}() has {branch_count} branches",
                file_path=file_path,
                line=line,
                details={"function": func_name, "branches": branch_count},
                proposed_action="Consider using match statements, lookup tables, or strategy pattern"
            )

        # Nested loops
        if nested_loops >= 2:
            self.add_finding(
                category="spaghetti",
                severity="medium",
                title=f"Nested loops in {func_name}()",
                file_path=file_path,
                line=line,
                details={"function": func_name, "nested_loops": nested_loops},
                proposed_action="Consider extracting inner loops to separate functions"
            )

    def _check_file_spaghetti(self, file_path: str, content: str, lines: List[str]):
        """Check file-level spaghetti patterns."""

        # Too many functions in one file
        func_count = len(re.findall(r'^func\s+', content, re.MULTILINE))
        if func_count > 30:
            self.add_finding(
                category="spaghetti",
                severity="medium",
                title=f"Too many functions: {func_count} in one file",
                file_path=file_path,
                details={"function_count": func_count},
                proposed_action="Split into multiple focused modules"
            )

        # God class (too many instance variables)
        var_count = len(re.findall(r'^var\s+', content, re.MULTILINE))
        if var_count > 25:
            self.add_finding(
                category="spaghetti",
                severity="medium",
                title=f"God class: {var_count} instance variables",
                file_path=file_path,
                details={"variable_count": var_count},
                proposed_action="Consider extracting related variables into component classes"
            )

        # Circular/tangled dependencies (many preloads)
        preload_count = len(re.findall(r'preload\s*\(', content))
        if preload_count > 10:
            self.add_finding(
                category="spaghetti",
                severity="low",
                title=f"Many dependencies: {preload_count} preloads",
                file_path=file_path,
                details={"preload_count": preload_count},
                proposed_action="Consider using dependency injection or autoloads"
            )

        # Magic numbers
        magic_numbers = re.findall(r'(?<![.\w])(\d{2,}\.?\d*)(?!\s*[:\]\)])', content)
        # Filter out common non-magic numbers
        magic_numbers = [n for n in magic_numbers if float(n) not in [0, 1, 2, 10, 100, 255, 360, 1000]]
        if len(magic_numbers) > 10:
            self.add_finding(
                category="spaghetti",
                severity="low",
                title=f"Magic numbers: {len(magic_numbers)} unexplained numeric literals",
                file_path=file_path,
                details={"count": len(magic_numbers), "examples": magic_numbers[:5]},
                proposed_action="Extract magic numbers to named constants"
            )

    def check_code_smells(self, gd_files: List[Path]):
        """Check for general code smells."""
        self.log("Checking for code smells...")

        smell_patterns = [
            # (pattern, category, severity, title, action)
            (r'#.*(?:temporary|temp|hack|workaround|kludge)', "code_smell", "low",
             "Temporary code comment", "Address temporary workaround"),
            (r'print\s*\(|prints\s*\(|printt\s*\(', "code_smell", "low",
             "Debug print statement", "Remove or use proper logging"),
            (r'pass\s*#.*todo', "code_smell", "medium",
             "Empty implementation with TODO", "Implement or remove"),
            (r'(\w+)\s*=\s*\1\s*[+\-*/]', "code_smell", "low",
             "Self-modifying assignment", "Use compound assignment (+=, -=, etc.)"),
            (r'if\s+\w+\s*==\s*true\s*:', "code_smell", "low",
             "Redundant boolean comparison", "Use 'if variable:' instead"),
            (r'if\s+\w+\s*==\s*false\s*:', "code_smell", "low",
             "Redundant boolean comparison", "Use 'if not variable:' instead"),
            (r'return\s+true\s*\n\s*else\s*:\s*\n\s*return\s+false', "code_smell", "low",
             "Verbose boolean return", "Simplify to 'return condition'"),
        ]

        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
            except:
                continue

            rel_path = str(file_path.relative_to(self.project_path))

            for pattern, category, severity, title, action in smell_patterns:
                matches = list(re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE))
                if matches:
                    # Find line number for first match
                    first_match = matches[0]
                    line_num = content[:first_match.start()].count('\n') + 1

                    self.add_finding(
                        category=category,
                        severity=severity,
                        title=f"{title} ({len(matches)} occurrence{'s' if len(matches) > 1 else ''})",
                        file_path=rel_path,
                        line=line_num,
                        details={"count": len(matches), "pattern": pattern},
                        proposed_action=action
                    )

    # =========================================================================
    # MAIN RUN
    # =========================================================================

    def run(self) -> Dict:
        """Run the full audit."""
        start_time = datetime.now()
        self.log("="*60)
        self.log("CODE AUDITOR - Starting comprehensive scan")
        self.log("="*60)
        self.log(f"Project: {self.project_path}")

        # Collect files
        gd_files, tscn_files = self.collect_files()

        # Parse all GDScript files
        self.log("Parsing GDScript files...")
        parse_results = {}
        for file_path in gd_files:
            rel_path = str(file_path.relative_to(self.project_path))
            parse_results[rel_path] = self.parse_gdscript(file_path)
            self.stats["files_parsed"] += 1

        # Analyze usage patterns
        self.log("Analyzing usage patterns...")
        for file_path in gd_files:
            try:
                content = file_path.read_text(encoding='utf-8', errors='ignore')
                self.analyze_gdscript_usage(file_path, content)
            except:
                pass

        # Parse scenes
        self.log("Parsing scene files...")
        for scene_path in tscn_files:
            self.parse_scene(scene_path)

        # Run all checks
        self.log("\n" + "="*60)
        self.log("Running audit checks...")
        self.log("="*60)

        self.check_unused_functions(gd_files)
        self.check_unused_signals()
        self.check_orphan_preloads(gd_files)
        self.check_empty_functions(parse_results)
        self.check_todos(parse_results)
        self.check_unused_classes()
        self.check_scene_script_references(tscn_files)
        self.check_duplicate_functions(gd_files)
        self.check_large_files(gd_files)
        self.check_performance_issues(gd_files)
        self.check_spaghetti_code(gd_files)
        self.check_code_smells(gd_files)

        # Generate report
        duration = (datetime.now() - start_time).total_seconds()

        report = {
            "audit_time": datetime.now().isoformat(),
            "duration_seconds": duration,
            "project_path": str(self.project_path),
            "stats": {
                "files_scanned": len(gd_files) + len(tscn_files),
                "gdscript_files": len(gd_files),
                "scene_files": len(tscn_files),
                "total_findings": len(self.findings),
                "by_category": dict(self.stats),
            },
            "summary": self._generate_summary(),
            "findings": self.findings,
            "proposed_cleanup": self._generate_cleanup_plan(),
        }

        self.log("\n" + "="*60)
        self.log("AUDIT COMPLETE")
        self.log("="*60)
        self.log(f"Duration: {duration:.1f}s")
        self.log(f"Files scanned: {len(gd_files) + len(tscn_files)}")
        self.log(f"Total findings: {len(self.findings)}")

        return report

    def _generate_summary(self) -> Dict:
        """Generate a summary of findings by category."""
        summary = defaultdict(lambda: {"count": 0, "items": []})

        for finding in self.findings:
            cat = finding["category"]
            summary[cat]["count"] += 1
            if len(summary[cat]["items"]) < 5:  # Top 5 per category
                summary[cat]["items"].append(finding["title"])

        return dict(summary)

    def _generate_cleanup_plan(self) -> List[Dict]:
        """Generate a prioritized cleanup plan."""
        plan = []

        # Group findings by severity
        by_severity = defaultdict(list)
        for f in self.findings:
            by_severity[f["severity"]].append(f)

        # High priority
        if by_severity["high"]:
            plan.append({
                "priority": 1,
                "title": "Critical Issues",
                "description": "These should be fixed immediately as they may cause runtime errors",
                "count": len(by_severity["high"]),
                "items": [f["title"] for f in by_severity["high"][:10]],
            })

        # Medium priority
        if by_severity["medium"]:
            plan.append({
                "priority": 2,
                "title": "Code Quality Issues",
                "description": "These indicate potential bugs or maintenance issues",
                "count": len(by_severity["medium"]),
                "items": [f["title"] for f in by_severity["medium"][:10]],
            })

        # Low priority
        if by_severity["low"]:
            plan.append({
                "priority": 3,
                "title": "Cleanup Opportunities",
                "description": "Dead code that can be safely removed",
                "count": len(by_severity["low"]),
                "items": [f["title"] for f in by_severity["low"][:10]],
            })

        return plan


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Code Auditor - Scan codebase for orphaned code and issues",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--output", "-o", default="audit_report.json",
                        help="Output file for the report (default: audit_report.json)")
    parser.add_argument("--summary", "-s", action="store_true",
                        help="Print summary to console")

    args = parser.parse_args()

    auditor = CodeAuditor(PROJECT_PATH)
    report = auditor.run()

    # Save report
    output_path = AGENT_DIR / args.output
    output_path.write_text(json.dumps(report, indent=2))
    print(f"\nReport saved to: {output_path}")

    # Print summary if requested
    if args.summary:
        print("\n" + "="*60)
        print("CLEANUP PLAN")
        print("="*60)
        for item in report["proposed_cleanup"]:
            print(f"\n[Priority {item['priority']}] {item['title']}")
            print(f"  {item['description']}")
            print(f"  Count: {item['count']}")
            for i, title in enumerate(item["items"][:5], 1):
                print(f"    {i}. {title}")


if __name__ == "__main__":
    main()
