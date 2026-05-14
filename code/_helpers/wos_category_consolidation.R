# ============================================================================
# wos_category_consolidation.R — collapse WoS subject categories into 15
# broad fields.
# ----------------------------------------------------------------------------
# Web of Science assigns each publication one or more semicolon-delimited
# subject categories (the WoS.Categories field). For regression and figures
# we need a smaller, balanced set of broad fields. This file implements the
# 15-category consolidation following Milojevic (2020), exposed as:
#
#   categorize_wos(s, return_type = c("primary", "all", "concatenated"))
#       Map a single category string to a broad field (or list of fields).
#   categorize_wos_vector(v, ...)
#       Vectorized version, used by add_broad_field().
#   add_broad_field(df, wos_column, new_column_name, ...)
#       Add a `broad_field` column to a data frame.
#   get_field_distribution(df, field_column = "broad_field")
#       Counts and shares per broad field.
#   print_category_mapping()
#       Pretty-print the underlying mapping (used by the demo block below).
#
# Running this file directly (Rscript wos_category_consolidation.R) prints
# the mapping and a small worked example. Sourcing it from another script
# only defines the helpers.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

wos_category_mapping <- list(
  
  # 1. AGRICULTURAL SCIENCES
  "Agricultural sciences" = c(
    "Agriculture, Dairy & Animal Science",
    "Agriculture, Multidisciplinary",
    "Agronomy",
    "Fisheries",
    "Food Science & Technology",
    "Forestry",
    "Green & Sustainable Science & Technology",
    "Horticulture"
  ),
  
  # 2. ASTRONOMY
  "Astronomy" = c(
    "Astronomy & Astrophysics"
  ),
  
  # 3. BIOLOGICAL SCIENCES
  "Biological sciences" = c(
    "Anatomy & Morphology",
    "Biochemical Research Methods",
    "Biochemistry & Molecular Biology",
    "Biodiversity Conservation",
    "Biology",
    "Biophysics",
    "Biotechnology & Applied Microbiology",
    "Cell & Tissue Engineering",
    "Cell Biology",
    "Developmental Biology",
    "Ecology",
    "Entomology",
    "Evolutionary Biology",
    "Genetics & Heredity",
    "Microbiology",
    "Mycology",
    "Nutrition & Dietetics",
    "Ornithology",
    "Paleontology",
    "Parasitology",
    "Physiology",
    "Plant Sciences",
    "Reproductive Biology",
    "Virology",
    "Zoology"
  ),
  
  # 4. CHEMISTRY
  "Chemistry" = c(
    "Chemistry, Analytical",
    "Chemistry, Applied",
    "Chemistry, Inorganic & Nuclear",
    "Chemistry, Medicinal",
    "Chemistry, Multidisciplinary",
    "Chemistry, Organic",
    "Chemistry, Physical",
    "Crystallography",
    "Electrochemistry",
    "Polymer Science",
    "Spectroscopy"
  ),
  
  # 5. COMPUTER SCIENCES
  "Computer sciences" = c(
    "Computer Science, Artificial Intelligence",
    "Computer Science, Cybernetics",
    "Computer Science, Hardware & Architecture",
    "Computer Science, Information Systems",
    "Computer Science, Interdisciplinary Applications",
    "Computer Science, Software Engineering",
    "Computer Science, Theory & Methods",
    "Medical Informatics"
  ),
  
  # 6. ENGINEERING
  "Engineering" = c(
    "Agricultural Engineering",
    "Automation & Control Systems",
    "Construction & Building Technology",
    "Energy & Fuels",
    "Engineering, Aerospace",
    "Engineering, Biomedical",
    "Engineering, Chemical",
    "Engineering, Civil",
    "Engineering, Electrical & Electronic",
    "Engineering, Environmental",
    "Engineering, Geological",
    "Engineering, Industrial",
    "Engineering, Manufacturing",
    "Engineering, Marine",
    "Engineering, Mechanical",
    "Engineering, Multidisciplinary",
    "Engineering, Ocean",
    "Engineering, Petroleum",
    "Imaging Science & Photographic Technology",
    "Instruments & Instrumentation",
    "Materials Science, Biomaterials",
    "Materials Science, Ceramics",
    "Materials Science, Characterization & Testing",
    "Materials Science, Coatings & Films",
    "Materials Science, Composites",
    "Materials Science, Multidisciplinary",
    "Materials Science, Paper & Wood",
    "Materials Science, Textiles",
    "Mathematical & Computational Biology",
    "Medical Laboratory Technology",
    "Metallurgy & Metallurgical Engineering",
    "Mining & Mineral Processing",
    "Nanoscience & Nanotechnology",
    "Neuroimaging",
    "Nuclear Science & Technology",
    "Operations Research & Management Science",
    "Remote Sensing",
    "Robotics",
    "Telecommunications",
    "Transportation",
    "Transportation Science & Technology"
  ),
  
  # 7. GEOSCIENCES
  "Geosciences" = c(
    "Environmental Sciences",
    "Environmental Studies",
    "Geochemistry & Geophysics",
    "Geography, Physical",
    "Geology",
    "Geosciences, Multidisciplinary",
    "Limnology",
    "Marine & Freshwater Biology",
    "Meteorology & Atmospheric Sciences",
    "Mineralogy",
    "Oceanography",
    "Soil Science",
    "Water Resources"
  ),
  
  # 8. HUMANITIES
  "Humanities" = c(
    "Archaeology",
    "Architecture",
    "Art",
    "Asian Studies",
    "Classics",
    "Cultural Studies",
    "Dance",
    "Ethics",
    "Ethnic Studies",
    "Film, Radio, Television",
    "Folklore",
    "History",
    "History & Philosophy Of Science",
    "History Of Social Sciences",
    "Humanities, Multidisciplinary",
    "Language & Linguistics",
    "Literary Reviews",
    "Literary Theory & Criticism",
    "Literature",
    "Literature, African, Australian, Canadian",
    "Literature, American",
    "Literature, British Isles",
    "Literature, German, Dutch, Scandinavian",
    "Literature, Romance",
    "Literature, Slavic",
    "Logic",
    "Medical Ethics",
    "Medieval & Renaissance Studies",
    "Music",
    "Philosophy",
    "Poetry",
    "Religion",
    "Theater",
    "Women's Studies"
  ),
  
  # 9. MATHEMATICAL SCIENCES
  "Mathematical sciences" = c(
    "Mathematics",
    "Mathematics, Applied",
    "Mathematics, Interdisciplinary Applications",
    "Statistics & Probability"
  ),
  
  # 10. MEDICAL SCIENCES
  "Medical sciences" = c(
    "Allergy",
    "Andrology",
    "Anesthesiology",
    "Audiology & Speech-Language Pathology",
    "Cardiac & Cardiovascular Systems",
    "Clinical Neurology",
    "Critical Care Medicine",
    "Dentistry, Oral Surgery & Medicine",
    "Dermatology",
    "Emergency Medicine",
    "Endocrinology & Metabolism",
    "Gastroenterology & Hepatology",
    "Geriatrics & Gerontology",
    "Health Policy & Services",
    "Hematology",
    "Immunology",
    "Infectious Diseases",
    "Integrative & Complementary Medicine",
    "Medicine, General & Internal",
    "Medicine, Research & Experimental",
    "Microscopy",
    "Neurosciences",
    "Nursing",
    "Obstetrics & Gynecology",
    "Oncology",
    "Ophthalmology",
    "Orthopedics",
    "Otorhinolaryngology",
    "Pathology",
    "Pediatrics",
    "Peripheral Vascular Disease",
    "Pharmacology & Pharmacy",
    "Psychiatry",
    "Public, Environmental & Occupational Health",
    "Radiology, Nuclear Medicine & Medical Imaging",
    "Rehabilitation",
    "Respiratory System",
    "Rheumatology",
    "Sport Sciences",
    "Substance Abuse",
    "Surgery",
    "Toxicology",
    "Transplantation",
    "Tropical Medicine",
    "Urology & Nephrology",
    "Veterinary Sciences"
  ),
  
  # 11. PHYSICS
  "Physics" = c(
    "Acoustics",
    "Mechanics",
    "Optics",
    "Physics, Applied",
    "Physics, Atomic, Molecular & Chemical",
    "Physics, Condensed Matter",
    "Physics, Fluids & Plasmas",
    "Physics, Mathematical",
    "Physics, Multidisciplinary",
    "Physics, Nuclear",
    "Physics, Particles & Fields",
    "Thermodynamics"
  ),
  
  # 12. PROFESSIONAL FIELDS
  "Professional fields" = c(
    "Business",
    "Business, Finance",
    "Communication",
    "Education & Educational Research",
    "Education, Scientific Disciplines",
    "Education, Special",
    "Ergonomics",
    "Family Studies",
    "Health Care Sciences & Services",
    "Hospitality, Leisure, Sport & Tourism",
    "Industrial Relations & Labor",
    "Information Science & Library Science",
    "Law",
    "Management",
    "Medicine, Legal",
    "Primary Health Care",
    "Social Work"
  ),
  
  # 13. PSYCHOLOGY
  "Psychology" = c(
    "Behavioral Sciences",
    "Psychology",
    "Psychology, Applied",
    "Psychology, Biological",
    "Psychology, Clinical",
    "Psychology, Developmental",
    "Psychology, Educational",
    "Psychology, Experimental",
    "Psychology, Mathematical",
    "Psychology, Multidisciplinary",
    "Psychology, Psychoanalysis",
    "Psychology, Social"
  ),
  
  # 14. SOCIAL SCIENCES
  "Social sciences" = c(
    "Agricultural Economics & Policy",
    "Anthropology",
    "Area Studies",
    "Criminology & Penology",
    "Demography",
    "Economics",
    "Geography",
    "Gerontology",
    "International Relations",
    "Linguistics",
    "Planning & Development",
    "Political Science",
    "Public Administration",
    "Social Issues",
    "Social Sciences, Biomedical",
    "Social Sciences, Interdisciplinary",
    "Social Sciences, Mathematical Methods",
    "Sociology",
    "Urban Studies"
  ),
  
  # 15. MULTIDISCIPLINARY SCIENCES
  # Note: This category includes journals like Nature, Science, and PNAS
  # that publish across multiple disciplines
  "Multidisciplinary Sciences" = c(
    "Multidisciplinary Sciences"
  )
)

# Create reverse mapping (category -> broad field)
create_reverse_mapping <- function(mapping_list) {
  reverse_map <- list()
  for (broad_field in names(mapping_list)) {
    for (category in mapping_list[[broad_field]]) {
      reverse_map[[category]] <- broad_field
    }
  }
  return(reverse_map)
}

category_to_field <- create_reverse_mapping(wos_category_mapping)

#' Categorize Web of Science Categories
#'
#' This function takes a WoS category string (which may contain multiple
#' semicolon-separated categories) and returns the consolidated broad field(s).
#'
#' @param wos_string Character string containing WoS categories separated by semicolons
#' @param return_type Either "primary" (most frequent field), "all" (all unique fields),
#'                    or "concatenated" (all fields concatenated with semicolons)
#' @param handle_uncategorized How to handle categories not in mapping: 
#'                             "keep" (keep original), "drop" (remove), or "flag" (mark as "Uncategorized")
#' @return Character string or vector depending on return_type
#'
#' @examples
#' categorize_wos("Computer Science, Artificial Intelligence; Robotics")
#' # Returns: "Computer Science & AI"
#'
#' categorize_wos("Engineering, Biomedical; Materials Science, Biomaterials", 
#'                return_type = "all")
#' # Returns: c("Engineering", "Materials Science")
#'
#'
categorize_wos <- function(wos_string, 
                           return_type = "primary",
                           handle_uncategorized = "flag") {
  
  # Handle NA or empty strings
  if (is.na(wos_string) || wos_string == "") {
    return(NA_character_)
  }
  
  # Split by semicolon and trim whitespace
  categories <- str_split(wos_string, ";")[[1]] %>%
    str_trim()
  
  # Map each category to its broad field
  broad_fields <- sapply(categories, function(cat) {
    field <- category_to_field[[cat]]
    if (is.null(field)) {
      # Handle uncategorized
      if (handle_uncategorized == "keep") {
        return(cat)
      } else if (handle_uncategorized == "flag") {
        return("Uncategorized")
      } else {
        return(NA_character_)
      }
    }
    return(field)
  }, USE.NAMES = FALSE)
  
  # Remove NAs
  broad_fields <- broad_fields[!is.na(broad_fields)]
  
  # Get unique fields
  unique_fields <- unique(broad_fields)
  
  if (length(unique_fields) == 0) {
    return(NA_character_)
  }
  
  # Return based on type
  if (return_type == "all") {
    return(unique_fields)
  } else if (return_type == "concatenated") {
    return(paste(unique_fields, collapse = "; "))
  } else {  # "primary" - return most frequent, or first if tie
    field_counts <- table(broad_fields)
    return(names(field_counts)[which.max(field_counts)])
  }
}

#' Vectorized version of categorize_wos
#' 
#' Apply categorize_wos to a vector of WoS category strings
#' 
#' @param wos_vector Vector of WoS category strings
#' @param return_type Same as categorize_wos
#' @param handle_uncategorized Same as categorize_wos
#' @return Vector of categorized fields
#' 
categorize_wos_vector <- function(wos_vector, 
                                  return_type = "primary",
                                  handle_uncategorized = "flag") {
  sapply(wos_vector, categorize_wos, 
         return_type = return_type,
         handle_uncategorized = handle_uncategorized,
         USE.NAMES = FALSE)
}

#' Apply categorization to a dataframe
#' 
#' Add a new column with broad field categorization to your dataframe
#' 
#' @param df Dataframe containing WoS data
#' @param wos_column Name of the column containing WoS categories
#' @param new_column_name Name for the new categorized column (default: "broad_field")
#' @param return_type Same as categorize_wos
#' @param handle_uncategorized Same as categorize_wos
#' @return Dataframe with new column added
#' 
#' @examples
#' df <- data.frame(
#'   title = c("Paper 1", "Paper 2"),
#'   wos_categories = c(
#'     "Computer Science, Artificial Intelligence; Robotics",
#'     "Medicine, General & Internal; Cardiology"
#'   )
#' )
#' df_categorized <- add_broad_field(df, "wos_categories")
#' 
add_broad_field <- function(df, 
                            wos_column,
                            new_column_name = "broad_field",
                            return_type = "primary",
                            handle_uncategorized = "flag") {
  
  df[[new_column_name]] <- categorize_wos_vector(
    df[[wos_column]],
    return_type = return_type,
    handle_uncategorized = handle_uncategorized
  )
  
  return(df)
}

#' Get summary statistics of broad field distribution
#' 
#' @param df Dataframe with categorized fields
#' @param field_column Name of the column containing broad fields
#' @return Dataframe with counts and percentages
#' 
get_field_distribution <- function(df, field_column = "broad_field") {
  df %>%
    count(!!sym(field_column), name = "count") %>%
    mutate(percentage = round(count / sum(count) * 100, 2)) %>%
    arrange(desc(count))
}

#' Print the mapping structure for reference
#' 
print_category_mapping <- function() {
  cat("\n========================================\n")
  cat("WoS Category Consolidation Mapping\n")
  cat("========================================\n\n")
  
  for (field in names(wos_category_mapping)) {
    n_categories <- length(wos_category_mapping[[field]])
    cat(sprintf("%-40s (%d categories)\n", field, n_categories))
  }
  
  cat("\n========================================\n")
  cat(sprintf("Total: %d broad fields covering %d specific categories\n",
              length(wos_category_mapping),
              length(unlist(wos_category_mapping))))
  cat("========================================\n\n")
}

# ============================================================================
# EXAMPLE USAGE (only runs when this file is executed directly, not sourced)
# ============================================================================

.is_main_invocation <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- args[grepl("^--file=", args)]
  if (length(hit) == 0) return(FALSE)
  this <- normalizePath(sub("^--file=", "", hit[1]), mustWork = FALSE)
  endsWith(this, "wos_category_consolidation.R")
})()

if (.is_main_invocation) {
  print_category_mapping()

  example1 <- categorize_wos("Computer Science, Artificial Intelligence; Robotics")
  cat("\nExample 1 - Single WoS entry:\n")
  cat("Input: 'Computer Science, Artificial Intelligence; Robotics'\n")
  cat("Output:", example1, "\n")

  example2 <- categorize_wos(
    "Engineering, Biomedical; Materials Science, Biomaterials",
    return_type = "all"
  )
  cat("\nExample 2 - Multiple broad fields:\n")
  cat("Input: 'Engineering, Biomedical; Materials Science, Biomaterials'\n")
  cat("Output:", paste(example2, collapse = ", "), "\n")

  cat("\n\nExample 3 - Apply to dataframe:\n")
  sample_df <- data.frame(
    paper_id = 1:5,
    wos_categories = c(
      "Computer Science, Artificial Intelligence; Robotics",
      "Medicine, General & Internal; Cardiology",
      "Chemistry, Multidisciplinary; Nanoscience & Nanotechnology",
      "Economics; Business; Management",
      "Engineering, Electrical & Electronic; Physics, Applied"
    ),
    stringsAsFactors = FALSE
  )
  sample_df_categorized <- add_broad_field(sample_df, "wos_categories")
  print(sample_df_categorized[, c("paper_id", "wos_categories", "broad_field")])

  cat("\n\nField distribution:\n")
  print(get_field_distribution(sample_df_categorized))
}