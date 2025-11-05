# Code Quality Refactoring Plan

Based on RubyCritic analysis conducted on 2025-11-04.

## Current Status

**Score Distribution:**
- **A (Excellent)**: 3 files - AwsConfig, SpecHelper, TestVips
- **B (Good)**: 2 files - JwtAuthenticator, JwtSetupSpec
- **C (Acceptable)**: 3 files - DockerEnvironmentSpec, LocalstackIntegrationSpec, PdfConverter
- **D (Needs Improvement)**: 7 files - App (45 smells), ImageUploader (19 smells), PdfDownloader (21 smells), UrlValidator (36 smells), and their specs

## Phase 1: Quick Wins ✅ COMPLETE

Low-risk improvements that increase code quality immediately.

- [x] Replace generic exception variable names (`e` → `error`) across all files
- [x] Add class/module documentation comments
- [x] Extract duplicate method calls to local variables in app.rb
- [x] Remove unused parameters (lambda_handler `context`, upload_images_to_s3 `unique_id`)

**Impact**: Successfully reduced 27 smells across the codebase

### Phase 1 Results:
- **JwtAuthenticator**: 19 → 15 smells (-4)
- **PdfConverter**: 18 → 14 smells (-4)
- **App**: 42 → 31 smells (-11)
- **ImageUploader**: 19 → 17 smells (-2)
- **PdfDownloader**: 21 → 19 smells (-2)
- **AwsConfig**: 3 → 2 smells (-1)
- **Other files**: ~3 additional smells removed
- **Total: 27 smells eliminated**
- **App.rb complexity**: 231.82 → 206.55 (-25.27 points)
- **lambda_handler flog score**: 102 → 78 (-24 points)

## Phase 2: Extract Reusable Components

Create shared infrastructure before refactoring main classes.

- [ ] Extract retry logic into a reusable RetryHandler module
- [ ] Refactor PdfDownloader to use RetryHandler module
- [ ] Refactor ImageUploader to use RetryHandler module and create ContentData value object
- [ ] Extract S3UrlParser class from UrlValidator to handle URL parsing
- [ ] Consolidate duplicate validation logic in UrlValidator

**Impact**: Reduces duplication in PdfDownloader (21 smells) and ImageUploader (19 smells)

## Phase 3: Extract Service Classes

Break down the monolithic app.rb (45 smells).

- [ ] Extract RequestValidator class from app.rb
- [ ] Extract WebhookNotifier class from app.rb
- [ ] Extract ResponseBuilder helper class from app.rb
- [ ] Refactor lambda_handler in app.rb to use extracted service classes

**Impact**: Reduces lambda_handler from 102 complexity to <40

## Phase 4: Targeted Complexity Reduction

Address remaining high-complexity methods.

- [ ] Simplify JwtAuthenticator#retrieve_secret method (complexity score: 29)
- [ ] Extract error handling logic in JwtAuthenticator to reduce duplication
- [ ] Refactor PdfConverter#convert_to_images to reduce complexity (score: 39)

**Impact**: Improve B-rated and C-rated files to A rating

## Phase 5: Validation

- [ ] Run full test suite after all changes
- [ ] Re-run RubyCritic to measure improvement

**Expected Outcome**: Improve overall code quality from current state (7 D-rated files) to mostly A/B ratings.

## Notes

- Run tests after each phase to ensure no regressions
- Run RubyCritic periodically to track progress
- Update this file as tasks are completed
