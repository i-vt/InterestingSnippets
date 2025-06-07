import uuid

def get_uuid():
  # Generate a random UUID (UUID4)
  generated_uuid = uuid.uuid4()
  return str(generated_uuid)
