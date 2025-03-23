# variables.tf (root variables)

variable "output_path" {
  description = "Path to store the output files"
  type        = string
  default     = "./cluster-analysis"
}