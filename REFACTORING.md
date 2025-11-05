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

## Phase 2: Extract Reusable Components ✅ COMPLETE

Create shared infrastructure before refactoring main classes.

- [x] Extract retry logic into a reusable RetryHandler module
- [x] Refactor PdfDownloader to use RetryHandler module
- [x] Refactor ImageUploader to use RetryHandler module and create ContentData value object
- [x] Extract S3UrlParser class from UrlValidator to handle URL parsing
- [x] Consolidate duplicate validation logic in UrlValidator

### Phase 2 Results:

- **RetryHandler module created**: A-rated, 41.54 complexity, 5 smells
- **PdfDownloader**: 19 → 11 smells (-8, -42%)
- **ImageUploader**: D → C rating, 19 → 14 smells (-5, -26%), 144.09 → 102.7 complexity (-29%)
- **S3UrlParser module created**: Centralized S3 URL parsing logic
- **UrlValidator**: C → B rating, 35 → 12 smells (-23, -66%!), 141.09 → 60.78 complexity (-57%!), 36 → 0 duplication
- **Tests**: All unit tests passing (42 new examples for S3UrlParser and UrlValidator)
- **Overall Score**: 71.27 → 78.18 (+6.91 points, +9.7% improvement)

**Key Achievements:**
- Eliminated ~200 lines of duplicate retry logic
- Eliminated all duplication in UrlValidator
- Created reusable, well-tested infrastructure modules
- Significantly improved maintainability and testability

## Phase 3: Extract Service Classes ✅ COMPLETE

Break down the monolithic app.rb (45 smells).

- [x] Extract RequestValidator class from app.rb
- [x] Extract WebhookNotifier class from app.rb
- [x] Extract ResponseBuilder helper class from app.rb
- [x] Refactor lambda_handler in app.rb to use extracted service classes

### Phase 3 Results:

- **RequestValidator created**: A-rated, 35.52 complexity, 6 smells
- **ResponseBuilder created**: A-rated, 5.68 complexity, 4 smells
- **WebhookNotifier created**: A-rated, 23.76 complexity, 5 smells
- **App.rb**: D → C rating, 45 → 21 smells (-24, -53%!), 231.82 → 142.08 complexity (-39%)
- **lambda_handler flog score**: 102 → 66 (-36 points, -35% reduction!)
- **Tests**: All unit tests passing (40 examples, 0 failures)
- **Overall Score**: 78.18 → 77.6 (-0.58 points, slight decrease due to new files)

**Key Achievements:**
- Created 3 well-structured, A-rated service classes
- Reduced lambda_handler complexity by 35%
- Reduced app.rb smell count by 53%
- Significantly improved code organization and maintainability
- All tests passing after refactoring

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
