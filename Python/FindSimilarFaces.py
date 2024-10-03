import os
import cv2

import numpy as np 

def detect_faces_dnn(image):
    """Detect faces using OpenCV's DNN face detector."""
    modelFile = "res10_300x300_ssd_iter_140000.caffemodel"
    configFile = "deploy.prototxt"
    net = cv2.dnn.readNetFromCaffe(configFile, modelFile)

    h, w = image.shape[:2]
    blob = cv2.dnn.blobFromImage(cv2.resize(image, (300, 300)), 1.0,
                                 (300, 300), (104.0, 177.0, 123.0))
    net.setInput(blob)
    detections = net.forward()

    faces = []
    for i in range(detections.shape[2]):
        confidence = detections[0, 0, i, 2]
        if confidence > 0.5:  # Confidence threshold
            box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
            (x, y, x1, y1) = box.astype("int")
            face = image[y:y1, x:x1]
            faces.append(cv2.cvtColor(face, cv2.COLOR_BGR2GRAY))

    return faces

def detect_faces(image_path):
    """Combine DNN and Haar Cascade face detection."""
    image = cv2.imread(image_path)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    # DNN face detection
    faces_dnn = detect_faces_dnn(image)
    
    # Haar Cascade fallback if DNN fails
    if not faces_dnn:
        face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        faces_haar = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))
        faces_haar = [gray[y:y+h, x:x+w] for (x, y, w, h) in faces_haar]
        return faces_haar

    return faces_dnn

def compare_faces(target_face, face_to_check):
    """Compare two faces using SIFT feature matching with error handling."""
    sift = cv2.SIFT_create()

    # Compute keypoints and descriptors
    kp1, des1 = sift.detectAndCompute(target_face, None)
    kp2, des2 = sift.detectAndCompute(face_to_check, None)

    # Check if descriptors are None or empty
    if des1 is None or des2 is None:
        return False

    # Match descriptors using BFMatcher with ratio test
    bf = cv2.BFMatcher(cv2.NORM_L2, crossCheck=False)
    matches = bf.knnMatch(des1, des2, k=2)

    # Apply ratio test to filter matches
    good_matches = []
    for m, n in matches:
        if m.distance < 0.75 * n.distance:
            good_matches.append(m)

    # Consider matches only if there are enough of them
    if len(good_matches) > 10:
        return True
    return False

def find_similar_faces(directory, target_image_path):
    """Recursively find all images with similar faces in a directory."""
    target_faces = detect_faces(target_image_path)
    similar_images = []

    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                file_path = os.path.join(root, file)
                try:
                    faces_in_image = detect_faces(file_path)
                    for face in faces_in_image:
                        for target_face in target_faces:
                            if compare_faces(target_face, face):
                                similar_images.append(file_path)
                                print(f"Found similar face in: {file_path}")
                                break
                except Exception as e:
                    print(f"Could not process {file_path}: {e}")
    
    return similar_images


# Example usage
target_image_path = 'Face-Shoulders/00058.png'
directory_to_search = 'outputs/Models/'

similar_images = find_similar_faces(directory_to_search, target_image_path)
print(f"Found {len(similar_images)} similar images.")
