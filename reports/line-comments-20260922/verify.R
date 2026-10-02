# Locate the annotated R files in an ASCII-only relative directory.
files <- list.files('after-r', pattern='[.]R$', full.names=TRUE)
# Require all three scripts so an empty file list cannot pass validation.
stopifnot(length(files) == 3L)
# Parse each pair without evaluating any installation or configuration code.
for (file in files) {
  # Parse the original expressions without source location attributes.
  before <- parse(file.path('before', basename(file)), keep.source=FALSE, encoding='UTF-8')
  # Parse the annotated expressions with the same encoding and options.
  after <- parse(file, keep.source=FALSE, encoding='UTF-8')
  # Fail if adding comments changed an expression.
  stopifnot(identical(before, after))
  # Record the completed comparison for this file.
  cat(basename(file), ': parse and expression equality PASS\n')
# Finish the verification loop.
}
