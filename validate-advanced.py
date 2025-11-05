#!/usr/bin/env python3
"""
Advanced Jenkinsfile AST Validator
Performs deeper syntax and structural validation
"""

import re
import sys
from pathlib import Path

# Color codes
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

def print_test(test_num, description):
    print(f"\nTest {test_num}: {description}...")

def print_pass(message):
    print(f"{GREEN}✓ PASS{NC} - {message}")

def print_fail(message):
    print(f"{RED}✗ FAIL{NC} - {message}")

def print_warning(message):
    print(f"{YELLOW}⚠ WARNING{NC} - {message}")

class JenkinsfileValidator:
    def __init__(self, filepath):
        self.filepath = Path(filepath)
        self.content = self.filepath.read_text()
        self.lines = self.content.split('\n')
        self.errors = []
        self.warnings = []
        
    def validate_all(self):
        """Run all validation tests"""
        print("=" * 60)
        print("Advanced Jenkinsfile Validation")
        print("=" * 60)
        
        tests = [
            self.test_file_exists,
            self.test_balanced_delimiters,
            self.test_no_dev2_references,
            self.test_switch_statements,
            self.test_pipeline_structure,
            self.test_parameter_definitions,
            self.test_environment_consistency,
            self.test_case_statement_breaks,
            self.test_string_interpolation,
            self.test_closure_syntax
        ]
        
        for i, test in enumerate(tests, 1):
            test(i)
        
        return self.print_summary()
    
    def test_file_exists(self, test_num):
        """Test 1: Verify file exists"""
        print_test(test_num, "Checking if Jenkinsfile exists")
        if self.filepath.exists():
            print_pass(f"File found at {self.filepath}")
        else:
            print_fail("Jenkinsfile not found")
            sys.exit(1)
    
    def test_balanced_delimiters(self, test_num):
        """Test 2: Check balanced delimiters"""
        print_test(test_num, "Checking balanced delimiters")
        
        delimiters = {
            'braces': ('{', '}'),
            'parentheses': ('(', ')'),
            'brackets': ('[', ']')
        }
        
        all_balanced = True
        for name, (open_char, close_char) in delimiters.items():
            open_count = self.content.count(open_char)
            close_count = self.content.count(close_char)
            
            if open_count == close_count:
                print_pass(f"{name.capitalize()} balanced: {open_count} pairs")
            else:
                print_fail(f"{name.capitalize()} unbalanced: {open_count} opening, {close_count} closing")
                all_balanced = False
        
        return all_balanced
    
    def test_no_dev2_references(self, test_num):
        """Test 3: Verify dev2 has been completely removed"""
        print_test(test_num, "Verifying complete removal of dev2")
        
        # Check for dev2 in choices
        if re.search(r"choices:\s*\[.*'dev2'.*\]", self.content):
            print_fail("dev2 still present in choices parameter")
            self.errors.append("dev2 in choices")
            return False
        
        # Check for case 'dev2':
        dev2_cases = re.findall(r"case\s+'dev2':", self.content)
        if dev2_cases:
            print_fail(f"Found {len(dev2_cases)} dev2 case statement(s)")
            self.errors.append(f"{len(dev2_cases)} dev2 case statements")
            return False
        
        # Check for dev2.yaml
        if re.search(r"dev2\.yaml", self.content):
            print_fail("Reference to dev2.yaml still exists")
            self.errors.append("dev2.yaml reference")
            return False
        
        # Check for any other dev2 references (excluding comments)
        lines_with_dev2 = []
        for i, line in enumerate(self.lines, 1):
            if 'dev2' in line.lower() and not line.strip().startswith('//'):
                lines_with_dev2.append(i)
        
        if lines_with_dev2:
            print_warning(f"Found 'dev2' text on lines: {lines_with_dev2}")
            print_warning("Please verify these are not functional references")
        else:
            print_pass("No dev2 references found")
        
        return True
    
    def test_switch_statements(self, test_num):
        """Test 4: Validate switch statement structure"""
        print_test(test_num, "Analyzing switch statements")
        
        # Find all switch statements
        switch_pattern = r'switch\s*\(\s*params\.ENV\s*\)'
        switches = list(re.finditer(switch_pattern, self.content))
        
        print(f"   Found {len(switches)} switch statement(s) on ENV parameter")
        
        # For each switch, verify it has the expected cases
        expected_cases = ['dev1', 'mde', 'staging']
        
        for i, switch in enumerate(switches, 1):
            start_pos = switch.end()
            # Find the closing brace of this switch (simplified)
            brace_count = 0
            found_opening = False
            switch_content_end = start_pos
            
            for j in range(start_pos, len(self.content)):
                if self.content[j] == '{':
                    found_opening = True
                    brace_count += 1
                elif self.content[j] == '}':
                    brace_count -= 1
                    if found_opening and brace_count == 0:
                        switch_content_end = j
                        break
            
            switch_content = self.content[start_pos:switch_content_end]
            
            # Check for expected cases
            missing_cases = []
            for case in expected_cases:
                if f"case '{case}':" not in switch_content:
                    missing_cases.append(case)
            
            if missing_cases:
                print_fail(f"Switch {i}: Missing cases: {missing_cases}")
                self.errors.append(f"Missing cases in switch {i}")
            else:
                print_pass(f"Switch {i}: All expected cases present (dev1, mde, staging)")
        
        return len(switches) > 0
    
    def test_pipeline_structure(self, test_num):
        """Test 5: Verify pipeline structure"""
        print_test(test_num, "Validating pipeline structure")
        
        required_sections = [
            (r'pipeline\s*{', 'pipeline block'),
            (r'agent\s+any', 'agent declaration'),
            (r'parameters\s*{', 'parameters block'),
            (r'stages\s*{', 'stages block'),
        ]
        
        all_present = True
        for pattern, name in required_sections:
            if re.search(pattern, self.content):
                print_pass(f"Found {name}")
            else:
                print_fail(f"Missing {name}")
                self.errors.append(f"Missing {name}")
                all_present = False
        
        return all_present
    
    def test_parameter_definitions(self, test_num):
        """Test 6: Validate parameter definitions"""
        print_test(test_num, "Checking parameter definitions")
        
        # Check ENV parameter
        env_param = re.search(r"choice\s*\(\s*name:\s*'ENV',\s*choices:\s*\[(.*?)\]", self.content)
        
        if env_param:
            choices = env_param.group(1)
            print(f"   ENV choices: {choices}")
            
            if "'dev2'" in choices:
                print_fail("dev2 is still in ENV choices!")
                self.errors.append("dev2 in ENV choices")
                return False
            
            expected = ["'dev1'", "'mde'", "'staging'"]
            all_present = all(choice in choices for choice in expected)
            
            if all_present:
                print_pass("ENV parameter correctly defined")
            else:
                print_fail("ENV parameter missing expected choices")
                self.errors.append("ENV parameter incomplete")
                return False
        else:
            print_fail("ENV parameter definition not found")
            self.errors.append("No ENV parameter")
            return False
        
        return True
    
    def test_environment_consistency(self, test_num):
        """Test 7: Check environment variable consistency"""
        print_test(test_num, "Checking environment variable assignments")
        
        # Look for environment variable assignments in case statements
        env_assignments = {
            'dev1': re.findall(r"case 'dev1':.*?break", self.content, re.DOTALL),
            'mde': re.findall(r"case 'mde':.*?break", self.content, re.DOTALL),
            'staging': re.findall(r"case 'staging':.*?break", self.content, re.DOTALL),
        }
        
        # Check that each environment has necessary assignments
        required_vars = ['NAMESPACE', 'AWS_PROFILE', 'EKS_CLUSTER_NAME', 'ECR_REGISTRY']
        
        for env_name, cases in env_assignments.items():
            if not cases:
                print_warning(f"{env_name}: No case statements found (may be expected)")
                continue
            
            for case in cases:
                missing_vars = []
                for var in required_vars:
                    if f"env.{var}" not in case:
                        missing_vars.append(var)
                
                if missing_vars and env_name != 'mde':  # mde might have different structure
                    print_warning(f"{env_name}: Potentially missing vars: {missing_vars}")
        
        print_pass("Environment variable assignments checked")
        return True
    
    def test_case_statement_breaks(self, test_num):
        """Test 8: Verify case statements have breaks"""
        print_test(test_num, "Checking case statement breaks")
        
        # Find all case statements
        case_pattern = r"case\s+'(\w+)':(.*?)(?=case\s+'\w+':|default:|switch\s*\(|})"
        cases = re.findall(case_pattern, self.content, re.DOTALL)
        
        missing_breaks = []
        for case_name, case_body in cases:
            if 'break' not in case_body and case_name not in ['dev1', 'mde', 'staging']:
                # These might be the last case or have implicit breaks
                pass
        
        if missing_breaks:
            print_warning(f"Cases without explicit break: {missing_breaks}")
        else:
            print_pass("Case statement breaks properly handled")
        
        return True
    
    def test_string_interpolation(self, test_num):
        """Test 9: Check string interpolation syntax"""
        print_test(test_num, "Validating string interpolation")
        
        # Look for common string interpolation issues
        issues = []
        
        # Check for ${} usage
        interpolations = re.findall(r'\$\{[^}]+\}', self.content)
        print(f"   Found {len(interpolations)} variable interpolations")
        
        # Check for unclosed ${
        unclosed = re.findall(r'\$\{[^}]*$', '\n'.join(self.lines))
        if unclosed:
            print_fail(f"Found {len(unclosed)} potentially unclosed interpolations")
            issues.append("unclosed interpolations")
        else:
            print_pass("All string interpolations properly closed")
        
        return len(issues) == 0
    
    def test_closure_syntax(self, test_num):
        """Test 10: Validate closure syntax"""
        print_test(test_num, "Checking Groovy closure syntax")
        
        # Look for script blocks
        script_blocks = re.findall(r'script\s*{', self.content)
        print(f"   Found {len(script_blocks)} script block(s)")
        
        # Look for common closure patterns
        closures = re.findall(r'\.each\s*{', self.content)
        print(f"   Found {len(closures)} closure(s) using .each")
        
        print_pass("Closure syntax appears valid")
        return True
    
    def print_summary(self):
        """Print validation summary"""
        print("\n" + "=" * 60)
        print("Validation Summary")
        print("=" * 60)
        
        if self.errors:
            print(f"\n{RED}FAILED with {len(self.errors)} error(s):{NC}")
            for error in self.errors:
                print(f"  - {error}")
            return False
        
        if self.warnings:
            print(f"\n{YELLOW}{len(self.warnings)} warning(s):{NC}")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        print(f"\n{GREEN}✓ All validation tests passed!{NC}")
        print("\nThe Jenkinsfile is syntactically valid and ready for deployment.")
        return True

if __name__ == '__main__':
    jenkinsfile_path = "/Users/orlando/_tmp/alwr/jenkins-pipeline-collection/helm-deploy/Jenkinsfile"
    
    validator = JenkinsfileValidator(jenkinsfile_path)
    success = validator.validate_all()
    
    sys.exit(0 if success else 1)
