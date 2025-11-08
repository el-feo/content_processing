# Test Refactoring Plan

## Status: In Progress - Phase 0 Complete

**Created:** 2025-11-08
**Last Updated:** 2025-11-08

---

## Baseline Metrics (Before Refactoring)

### Test Coverage (as of 2025-11-08)
- **Line Coverage**: 65.43% (371 / 567 lines)
- **Branch Coverage**: 49.72% (88 / 177 branches)
- **Target**: 100% line and branch coverage

### Code Quality (RubyCritic)
**A-Rated Classes** (7 files):
- AwsConfig, RequestValidator, ResponseBuilder, RetryHandler
- SpecHelper, TestVips, UrlUtils, WebhookNotifier

**B-Rated Classes** (5 files):
- App.rb (complexity: 89.03, 11 smells)
- JwtAuthenticator (complexity: 73.11, 15 smells)
- JwtSetupSpec, PdfDownloader (complexity: 79.4, 9 smells)
- S3UrlParser, UrlValidator

**C-Rated Classes** (4 files):
- DockerEnvironmentSpec (duplication: 54)
- ImageUploader (complexity: 139.56, 19 smells)
- LocalstackIntegrationSpec, PdfConverter (complexity: 102.93, 20 smells)

**D-Rated Test Files** (4 files):
- ImageUploaderSpec, PdfConverterSpec, PdfDownloaderSpec, UrlValidatorSpec
- Issues: High complexity in tests, code duplication

**F-Rated Test Files** (2 files):
- AuthenticatedHandlerSpec (complexity: 520.98, duplication: 368, 15 smells)
- ErrorHandlingSpec (complexity: 436.8, duplication: 40, 12 smells)

### Test Suite Status
- **Total Tests**: 83 examples
- **Failures**: 5 (integration test mocking issues)
- **Pending**: 12 (ruby-vips not available locally)

---

## Current State Analysis

### Issues Identified

1. **Structure misalignment**: Test structure doesn't mirror application structure (`app/` and `lib/` directories not reflected in specs)
2. **Missing coverage**: No unit tests for 5 classes:
   - `app/request_validator.rb`
   - `app/response_builder.rb`
   - `app/webhook_notifier.rb`
   - `lib/aws_config.rb`
   - `lib/url_utils.rb`
3. **Mixed concerns**: Integration tests mix concerns (full handler tests vs. component integration)
4. **Low-value tests**: Infrastructure tests (`jwt_setup_spec.rb`, `docker_environment_spec.rb`) that don't add value
5. **Misplaced tests**: `error_handling_spec.rb` tests PdfDownloader behavior, not a distinct unit
6. **Orphan files**: `test_with_localstack.rb`, `pdf_converter/test_vips.rb`

### Current Test Files

**Unit Tests (spec/unit/):**

- `docker_environment_spec.rb` - Infrastructure test, low value
- `error_handling_spec.rb` - Actually tests PdfDownloader, misplaced
- `image_uploader_spec.rb` - Good unit test
- `jwt_authenticator_spec.rb` - Good unit test
- `pdf_converter_spec.rb` - Good unit test
- `pdf_downloader_spec.rb` - Good unit test
- `retry_handler_spec.rb` - Good unit test
- `s3_url_parser_spec.rb` - Good unit test
- `url_validator_spec.rb` - Good unit test

**Integration Tests (spec/integration/):**

- `authenticated_handler_spec.rb` - Duplicates unit test coverage
- `localstack_integration_spec.rb` - Good integration test, keep
- `pdf_download_integration_spec.rb` - Covered by unit tests

**Infrastructure Tests (spec/infrastructure/):**

- `jwt_setup_spec.rb` - Low value, just checks gems are installed

**Orphan Files:**

- `test_with_localstack.rb` (root level)
- `pdf_converter/test_vips.rb`

---

## Proposed Test Structure

```
spec/
├── spec_helper.rb                    # Keep, update if needed
├── support/                          # Test helpers and shared contexts
│   ├── jwt_helper.rb                 # Extract JWT test helpers
│   └── s3_stub_helper.rb             # Extract S3 stubbing helpers
├── fixtures/                         # Keep test fixtures
├── app_spec.rb                       # NEW: Unit tests for app.rb helper functions
├── app/                              # NEW: Mirror app/ directory
│   ├── image_uploader_spec.rb        # Reorganized from unit/
│   ├── jwt_authenticator_spec.rb     # Reorganized from unit/
│   ├── pdf_converter_spec.rb         # Reorganized from unit/
│   ├── pdf_downloader_spec.rb        # Reorganized from unit/
│   ├── request_validator_spec.rb     # NEW
│   ├── response_builder_spec.rb      # NEW
│   ├── url_validator_spec.rb         # Reorganized from unit/
│   └── webhook_notifier_spec.rb      # NEW
├── lib/                              # NEW: Mirror lib/ directory
│   ├── aws_config_spec.rb            # NEW
│   ├── retry_handler_spec.rb         # Reorganized from unit/
│   ├── s3_url_parser_spec.rb         # Reorganized from unit/
│   └── url_utils_spec.rb             # NEW
└── integration/
    └── localstack_integration_spec.rb  # Keep, enhance for full system verification
```

---

## Implementation Plan

### Phase 0: Setup Coverage and Quality Tools ✅ COMPLETE

**Objective:** Establish baseline metrics and tooling

**Tasks:**
- [x] Add SimpleCov gem to Gemfile
- [x] Configure SimpleCov in spec_helper.rb
- [x] Set coverage requirements (100% line and branch)
- [x] Run baseline coverage report
- [x] Run RubyCritic analysis
- [x] Document baseline metrics

**Results:**
- SimpleCov configured with 100% line and branch coverage requirements
- Baseline: 65.43% line coverage, 49.72% branch coverage
- RubyCritic analysis complete (see baseline metrics above)

---

### Phase 1: Cleanup ✅ COMPLETE

**Objective:** Remove outdated and low-value tests

**Tasks:**

- [x] Delete `spec/unit/` directory entirely (9 test files)
- [x] Delete `spec/integration/authenticated_handler_spec.rb`
- [x] Delete `spec/integration/pdf_download_integration_spec.rb`
- [x] Delete `spec/infrastructure/` directory
- [x] Delete `test_with_localstack.rb` (root level)
- [x] Delete `pdf_converter/test_vips.rb`
- [x] Commit cleanup changes

**Rationale:**

- `spec/unit/` tests will be reorganized to match app structure
- Integration tests duplicate unit test coverage
- Infrastructure tests don't add value (just check gems are installed)
- Orphan test files are outdated

**Results:**

- Deleted 13 test files and 3 directories
- Only `spec/integration/localstack_integration_spec.rb` remains for integration testing
- Ready to create new structure that mirrors application code

---

### Phase 2: Create New Directory Structure ⏳ NOT STARTED

**Objective:** Set up directory structure that mirrors application code

**Tasks:**

- [ ] Create `spec/app/` directory
- [ ] Create `spec/lib/` directory
- [ ] Create `spec/support/` directory
- [ ] Verify structure matches application layout

---

### Phase 3: Create Test Support Files ⏳ NOT STARTED

**Objective:** Extract common test helpers for reusability

**Tasks:**

- [ ] Create `spec/support/jwt_helper.rb` with JWT test utilities
- [ ] Create `spec/support/s3_stub_helper.rb` with S3 stubbing helpers
- [ ] Update `spec_helper.rb` to load support files
- [ ] Test that support files are properly loaded

**Test Utilities to Extract:**

- JWT token generation (valid, expired, invalid signature)
- S3 request stubbing patterns
- Common mock setup for AWS services

---

### Phase 4: Create Unit Tests for app/ Classes ⏳ NOT STARTED

**Objective:** Create comprehensive unit tests following best practices

**Best Practices:**

- Test only the class in isolation
- Mock/stub all dependencies
- Follow RSpec structure: describe/context/it
- Focus on behavior, not implementation
- Test happy path, edge cases, and error conditions
- Use descriptive test names

**Tasks:**

#### 4.1: Create spec/app_spec.rb

- [ ] Test `process_pdf_conversion` function
- [ ] Test `handle_failure` function
- [ ] Test `notify_webhook` function
- [ ] Test `send_webhook` function
- [ ] Test `authenticate_request` function
- [ ] Test `lambda_handler` orchestration

#### 4.2: Reorganize existing app/ specs

- [ ] Move `spec/unit/image_uploader_spec.rb` → `spec/app/image_uploader_spec.rb`
- [ ] Move `spec/unit/jwt_authenticator_spec.rb` → `spec/app/jwt_authenticator_spec.rb`
- [ ] Move `spec/unit/pdf_converter_spec.rb` → `spec/app/pdf_converter_spec.rb`
- [ ] Move `spec/unit/pdf_downloader_spec.rb` → `spec/app/pdf_downloader_spec.rb`
- [ ] Move `spec/unit/url_validator_spec.rb` → `spec/app/url_validator_spec.rb`
- [ ] Refactor moved tests to ensure proper isolation and mocking
- [ ] Incorporate relevant tests from `spec/unit/error_handling_spec.rb` into `pdf_downloader_spec.rb`

#### 4.3: Create missing app/ specs

- [ ] Create `spec/app/request_validator_spec.rb`
  - Test body parsing
  - Test required field validation
  - Test unique_id format validation
  - Test error response generation
- [ ] Create `spec/app/response_builder_spec.rb`
  - Test success responses
  - Test error responses
  - Test authentication error responses
  - Test CORS headers
- [ ] Create `spec/app/webhook_notifier_spec.rb`
  - Test successful notification
  - Test retry logic
  - Test timeout handling
  - Test error responses

---

### Phase 5: Create Unit Tests for lib/ Classes ⏳ NOT STARTED

**Objective:** Create unit tests for library utilities

**Tasks:**

#### 5.1: Reorganize existing lib/ specs

- [ ] Move `spec/unit/retry_handler_spec.rb` → `spec/lib/retry_handler_spec.rb`
- [ ] Move `spec/unit/s3_url_parser_spec.rb` → `spec/lib/s3_url_parser_spec.rb`
- [ ] Refactor moved tests to ensure proper isolation

#### 5.2: Create missing lib/ specs

- [ ] Create `spec/lib/aws_config_spec.rb`
  - Test AWS client configuration
  - Test region configuration
  - Test endpoint configuration (for LocalStack)
  - Test credential handling
- [ ] Create `spec/lib/url_utils_spec.rb`
  - Test URL manipulation functions
  - Test URL validation
  - Test URL sanitization

---

### Phase 6: Enhance Integration Tests ⏳ NOT STARTED

**Objective:** Create comprehensive end-to-end test for LocalStack

**Tasks:**

- [ ] Review existing `spec/integration/localstack_integration_spec.rb`
- [ ] Enhance to cover complete workflow:
  - Lambda handler invocation with real event
  - JWT authentication flow
  - S3 download from LocalStack
  - PDF conversion
  - S3 upload to LocalStack
  - Webhook notification
- [ ] Add error scenario coverage:
  - Invalid JWT
  - Missing S3 object
  - Invalid PDF
  - S3 upload failure
- [ ] Document LocalStack setup requirements
- [ ] Add clear comments about what this test verifies

---

### Phase 7: Update Test Configuration ⏳ NOT STARTED

**Objective:** Improve test setup and documentation

**Tasks:**

- [ ] Update `spec_helper.rb`:
  - Load support files
  - Add shared configuration
  - Document test environment setup
- [ ] Update `.rspec` file if needed
- [ ] Create/update `spec/README.md` with:
  - How to run tests
  - How to run unit tests only
  - How to run integration tests with LocalStack
  - Test organization explanation
- [ ] Update main `CLAUDE.md` with new test structure

---

### Phase 8: Verification and Cleanup ⏳ NOT STARTED

**Objective:** Ensure all tests pass with 100% coverage and improved code quality

**Tasks:**

- [ ] Run all unit tests: `bundle exec rspec spec/app spec/lib spec/app_spec.rb --format documentation`
- [ ] Run integration tests: `bundle exec rspec spec/integration --format documentation`
- [ ] Run full test suite: `bundle exec rspec`
- [ ] Verify 100% line coverage achieved
- [ ] Verify 100% branch coverage achieved (all conditionals tested)
- [ ] Run RubyCritic: `~/.claude/skills/rubycritic/scripts/check_quality.sh`
- [ ] Verify no F-rated test files (all should be A or B)
- [ ] Check for test duplication and refactor if needed
- [ ] Check for any remaining orphan test files
- [ ] Generate final coverage report for documentation
- [ ] Final commit with summary of changes

**Success Criteria:**

- All tests passing (0 failures, 0 pending except ruby-vips)
- 100% line coverage
- 100% branch coverage
- All test files rated A or B in RubyCritic
- Zero test code duplication
- Test suite runs in under 60 seconds (unit tests only)

---

## Testing Best Practices Applied

### Unit Test Principles

1. **Isolation**: Each test tests only one class
2. **Fast**: No network calls, no file I/O (except minimal temp files)
3. **Deterministic**: Same input always produces same output
4. **Clear**: Descriptive test names that explain what's being tested
5. **Focused**: One assertion per test when possible

### Test Structure

```ruby
RSpec.describe ClassName do
  describe '#method_name' do
    context 'when condition' do
      it 'does expected behavior' do
        # Arrange
        # Act
        # Assert
      end
    end
  end
end
```

### Mocking Strategy

- Mock external services (AWS, HTTP calls)
- Stub file system when possible
- Use real objects for simple value objects
- Verify interactions when testing side effects

---

## Benefits of New Structure

1. **Clear organization**: Test structure mirrors application structure
2. **Complete coverage**: Every class has a corresponding test file
3. **Fast feedback**: Properly mocked unit tests run in milliseconds
4. **Meaningful integration**: Single LocalStack test verifies full system
5. **Maintainability**: Easy to find tests for any given class
6. **Onboarding**: New developers can understand test organization immediately
7. **Best practices**: Follows RSpec and Rails testing conventions

---

## Progress Tracking

### Summary

- **Phase 0**: ✅ Complete (Coverage and quality tools setup)
- **Phase 1**: ⏳ Not Started (Cleanup)
- **Phase 2**: ⏳ Not Started (Directory structure)
- **Phase 3**: ⏳ Not Started (Support files)
- **Phase 4**: ⏳ Not Started (App tests)
- **Phase 5**: ⏳ Not Started (Lib tests)
- **Phase 6**: ⏳ Not Started (Integration tests)
- **Phase 7**: ⏳ Not Started (Test configuration)
- **Phase 8**: ⏳ Not Started (Verification)

### Coverage Progress

- **Baseline**: 65.43% line, 49.72% branch
- **Current**: TBD (will update after each phase)
- **Target**: 100% line, 100% branch

### Metrics

- **Files to Delete**: 8
- **Directories to Create**: 3
- **Tests to Move**: 9
- **Tests to Create**: 8
- **Support Files to Create**: 2
- **Total Test Files (After)**: 18
- **Expected Coverage Gain**: +34.57% line, +50.28% branch

---

## Notes

### Files to Preserve

These test files contain good tests and should be moved/refactored:

- `spec/unit/image_uploader_spec.rb`
- `spec/unit/jwt_authenticator_spec.rb`
- `spec/unit/pdf_converter_spec.rb`
- `spec/unit/pdf_downloader_spec.rb`
- `spec/unit/retry_handler_spec.rb`
- `spec/unit/s3_url_parser_spec.rb`
- `spec/unit/url_validator_spec.rb`
- `spec/integration/localstack_integration_spec.rb`

### Test Extraction Notes

From `spec/unit/error_handling_spec.rb`:

- All retry logic tests should be incorporated into `pdf_downloader_spec.rb`
- Tests are well-written and should be preserved

From `spec/integration/authenticated_handler_spec.rb`:

- Authentication tests should be in `jwt_authenticator_spec.rb`
- Request validation tests should be in `request_validator_spec.rb`
- Handler orchestration can inspire `app_spec.rb` tests
- Don't duplicate - extract patterns for reuse
