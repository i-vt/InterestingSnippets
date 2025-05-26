import os
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.transforms as transforms
from torchvision.datasets import ImageFolder
from torch.utils.data import DataLoader, random_split
from torchvision import models
import matplotlib.pyplot as plt
import numpy as np
import cv2
from torchvision.transforms.functional import to_pil_image

# Configuration
DATA_DIR = "data"
BATCH_SIZE = 16
NUM_EPOCHS = 5
LEARNING_RATE = 0.001
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Transforms
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
])

# Dataset and DataLoader
dataset = ImageFolder(DATA_DIR, transform=transform)
train_loader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=True)

# Model
model = models.resnet18(pretrained=True)
model.fc = nn.Linear(model.fc.in_features, len(dataset.classes))
model = model.to(DEVICE)

# Loss and Optimizer
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE)

# Training
print("Starting training...")
for epoch in range(NUM_EPOCHS):
    model.train()
    running_loss = 0.0
    correct = 0
    total = 0
    
    for images, labels in train_loader:
        images, labels = images.to(DEVICE), labels.to(DEVICE)
        
        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        
        running_loss += loss.item() * images.size(0)
        _, predicted = torch.max(outputs, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

    epoch_loss = running_loss / len(dataset)
    accuracy = correct / total
    print(f"Epoch {epoch+1}/{NUM_EPOCHS} | Loss: {epoch_loss:.4f} | Accuracy: {accuracy:.4f}")

torch.save(model.state_dict(), "model.pth")
print("Training complete. Model saved as model.pth")

# Grad-CAM Visualization
def show_gradcam(model, image_tensor, label_idx, class_names):
    model.eval()
    features = []
    gradients = []

    def forward_hook(module, input, output):
        features.append(output)

    def backward_hook(module, grad_in, grad_out):
        gradients.append(grad_out[0])
    
    final_conv = model.layer4[-1].conv2
    forward_handle = final_conv.register_forward_hook(forward_hook)
    backward_handle = final_conv.register_backward_hook(backward_hook)

    image_tensor = image_tensor.unsqueeze(0).to(DEVICE)
    output = model(image_tensor)
    model.zero_grad()
    class_loss = output[0, label_idx]
    class_loss.backward()

    grad = gradients[0].squeeze(0)
    fmap = features[0].squeeze(0)
    
    weights = grad.mean(dim=(1, 2))
    cam = torch.zeros(fmap.shape[1:], dtype=torch.float32)

    for i, w in enumerate(weights):
        cam += w * fmap[i]

    cam = cam.clamp(min=0)
    cam = cam - cam.min()
    cam = cam / cam.max()
    cam = cam.cpu().numpy()
    cam = cv2.resize(cam, (224, 224))

    orig_img = to_pil_image(image_tensor.squeeze(0).cpu())
    heatmap = cv2.applyColorMap(np.uint8(255 * cam), cv2.COLORMAP_JET)
    heatmap = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)
    heatmap = np.array(heatmap)
    overlay = (0.4 * np.array(orig_img) + 0.6 * heatmap).astype(np.uint8)

    plt.figure(figsize=(10, 4))
    plt.subplot(1, 3, 1)
    plt.title("Original")
    plt.imshow(orig_img)
    plt.axis("off")

    plt.subplot(1, 3, 2)
    plt.title("Grad-CAM Heatmap")
    plt.imshow(heatmap)
    plt.axis("off")

    plt.subplot(1, 3, 3)
    plt.title(f"Overlay: {class_names[label_idx]}")
    plt.imshow(overlay)
    plt.axis("off")

    plt.tight_layout()
    plt.show()

    forward_handle.remove()
    backward_handle.remove()

# Visualize Grad-CAM on one example
sample_img, label_idx = dataset[0]
show_gradcam(model, sample_img, label_idx, dataset.classes)
