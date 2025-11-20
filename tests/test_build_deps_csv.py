#!/usr/bin/env python3
"""
Tests for build-deps-csv.py script
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import the module (without .py extension)
import importlib.util
spec = importlib.util.spec_from_file_location("build_deps_csv", 
    Path(__file__).parent.parent / "build-deps-csv.py")
build_deps_csv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_deps_csv)


class TestDependencyScanner(unittest.TestCase):
    """Test cases for DependencyScanner class"""

    def setUp(self):
        """Set up test fixtures"""
        self.test_dir = tempfile.mkdtemp()
        self.scanner = build_deps_csv.DependencyScanner(self.test_dir)

    def tearDown(self):
        """Clean up test fixtures"""
        import shutil
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_parse_package_json(self):
        """Test parsing package.json content"""
        content = '''
        {
          "dependencies": {
            "express": "^4.17.1",
            "lodash": "^4.17.21"
          }
        }
        '''
        result = self.scanner.parse_package_json(content, Path("package.json"))
        self.assertEqual(len(result), 2)
        self.assertIn(("express", "^4.17.1"), result)
        self.assertIn(("lodash", "^4.17.21"), result)

    def test_parse_requirements_txt(self):
        """Test parsing requirements.txt content"""
        content = '''
        requests>=2.25.1
        flask==1.1.2
        numpy
        # This is a comment
        django>=3.0
        '''
        result = self.scanner.parse_requirements(content, Path("requirements.txt"))
        self.assertEqual(len(result), 4)
        self.assertIn(("requests", ">=2.25.1"), result)
        self.assertIn(("flask", "==1.1.2"), result)
        self.assertIn(("numpy", "*"), result)
        self.assertIn(("django", ">=3.0"), result)

    def test_parse_go_mod(self):
        """Test parsing go.mod content"""
        content = '''
        module example.com/myapp
        
        go 1.19
        
        require (
            github.com/gin-gonic/gin v1.7.7
            github.com/stretchr/testify v1.7.0
        )
        '''
        result = self.scanner.parse_go_mod(content, Path("go.mod"))
        self.assertGreaterEqual(len(result), 2)
        # Check if we found at least the major packages
        package_names = [name for name, _ in result]
        self.assertTrue(any("gin" in name for name in package_names))

    def test_parse_gemfile(self):
        """Test parsing Gemfile content"""
        content = '''
        gem 'rails', '6.1.0'
        gem 'pg'
        gem "redis", "4.2.5"
        '''
        result = self.scanner.parse_gemfile(content, Path("Gemfile"))
        self.assertGreaterEqual(len(result), 3)
        package_names = [name for name, _ in result]
        self.assertIn('rails', package_names)
        self.assertIn('pg', package_names)

    def test_directory_pruning(self):
        """Test that .git and other directories are pruned"""
        # Create test directory structure
        git_dir = Path(self.test_dir) / ".git"
        node_modules = Path(self.test_dir) / "node_modules"
        git_dir.mkdir()
        node_modules.mkdir()
        
        # Create package.json in both directories
        (git_dir / "package.json").write_text('{"dependencies": {"test": "1.0.0"}}')
        (node_modules / "package.json").write_text('{"dependencies": {"test": "1.0.0"}}')
        (Path(self.test_dir) / "package.json").write_text('{"dependencies": {"valid": "1.0.0"}}')
        
        # Scan
        deps = self.scanner.scan()
        
        # Should only find the valid one, not in .git or node_modules
        self.assertEqual(len(deps), 1)
        self.assertEqual(deps[0]['package'], 'valid')

    def test_parse_cargo_toml(self):
        """Test parsing Cargo.toml content"""
        content = '''
        [package]
        name = "myapp"
        version = "0.1.0"
        
        [dependencies]
        serde = "1.0"
        tokio = "1.17"
        '''
        result = self.scanner.parse_cargo(content, Path("Cargo.toml"))
        self.assertEqual(len(result), 2)
        self.assertIn(("serde", "1.0"), result)
        self.assertIn(("tokio", "1.17"), result)

    def test_error_handling_invalid_file(self):
        """Test error handling for invalid files"""
        # Create an invalid file that can't be read
        invalid_file = Path(self.test_dir) / "invalid.json"
        invalid_file.write_text("not json at all")
        
        # This should not crash, just handle the error gracefully
        deps = self.scanner.scan()
        # Should return empty list since no valid dependencies found
        self.assertIsInstance(deps, list)


class TestRegexPatterns(unittest.TestCase):
    """Test pre-compiled regex patterns"""

    def test_package_json_pattern(self):
        """Test package.json regex pattern"""
        pattern = build_deps_csv.PACKAGE_JSON_PATTERN
        test_string = '"lodash": "^4.17.21"'
        match = pattern.search(test_string)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "lodash")
        self.assertEqual(match.group(2), "^4.17.21")

    def test_requirements_pattern(self):
        """Test requirements.txt regex pattern"""
        pattern = build_deps_csv.REQUIREMENTS_PATTERN
        
        # Test various formats
        self.assertIsNotNone(pattern.match("requests>=2.25.1"))
        self.assertIsNotNone(pattern.match("flask==1.1.2"))
        self.assertIsNotNone(pattern.match("numpy"))
        self.assertIsNotNone(pattern.match("django~=3.0"))

    def test_go_mod_pattern(self):
        """Test go.mod regex pattern"""
        pattern = build_deps_csv.GO_MOD_PATTERN
        test_string = "    github.com/gin-gonic/gin v1.7.7"
        match = pattern.match(test_string)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "github.com/gin-gonic/gin")
        self.assertEqual(match.group(2), "1.7.7")


class TestPruneDirectories(unittest.TestCase):
    """Test directory pruning configuration"""

    def test_prune_dirs_set(self):
        """Test that PRUNE_DIRS contains expected directories"""
        prune_dirs = build_deps_csv.PRUNE_DIRS
        self.assertIn('.git', prune_dirs)
        self.assertIn('node_modules', prune_dirs)
        self.assertIn('__pycache__', prune_dirs)
        self.assertIn('venv', prune_dirs)


if __name__ == '__main__':
    unittest.main()
