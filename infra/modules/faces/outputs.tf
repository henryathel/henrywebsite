output "function_arn" {
  description = "Viewer-request function that picks a random face for /img/henry-ashton.jpg."
  value       = aws_cloudfront_function.random_face.arn
}

output "face_count" {
  description = "Number of faces in the pool the function picks from."
  value       = local.face_count
}
