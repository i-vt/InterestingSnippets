# install_and_load_libraries
# Example usage:
# 1. Define the libraries to load
# required_libraries <- c("ggplot2", "rpart.plot")
# 2. Use the function to install and load the libraries
# install_and_load_libraries(required_libraries)


install_and_load_libraries <- function(libraries) {
  for (library_import in libraries) {
    if (!requireNamespace(library_import, quietly = TRUE)) {
      install.packages(library_import)
    }
    library(library_import, character.only = TRUE)
  }
}

