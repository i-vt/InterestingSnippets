import sys
import torch
import torch.nn as nn
from torchvision import models, transforms
from torchvision.datasets import ImageFolder
from PIL import Image

# Configuration
MODEL_PATH = "model.pth"
DATA_DIR = "data"
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Load class names from training dataset
dataset = ImageFolder(DATA_DIR)
class_names = dataset.classes

# Load the model
model = models.resnet18(pretrained=False)
model.fc = nn.Linear(model.fc.in_features, len(class_names))
model.load_state_dict(torch.load(MODEL_PATH, map_location=DEVICE))
model = model.to(DEVICE)
model.eval()

# Image transform (same as training)
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
])

# Predict function
def predict_image(image_path):
    try:
        image = Image.open(image_path).convert('RGB')
    except Exception as e:
        print(f"Error loading image: {e}")
        sys.exit(1)

    input_tensor = transform(image).unsqueeze(0).to(DEVICE)

    with torch.no_grad():
        output = model(input_tensor)
        _, predicted_idx = torch.max(output, 1)
        predicted_class = class_names[predicted_idx.item()]

    print(f"Predicted class: {predicted_class}")

# Entry point
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python predict.py path_to_image.jpg")
        sys.exit(1)

    image_path = sys.argv[1]
    predict_image(image_path)
