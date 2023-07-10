# Decision trees are a simple and intuitive type of machine learning algorithm. They use a tree-like structure to make decisions based on features or attributes of the data. Decision trees are easy to visualize and interpret, making them popular for both classification and regression tasks. They can handle both categorical and numerical data and can be extended to handle complex relationships through ensemble methods like random forests or gradient boosting.

from sklearn.tree import DecisionTreeClassifier

# Example dataset
X = [[1], [2], [3], [4], [5]]
y = [0, 0, 1, 1, 1]

# Create and fit the decision tree model
model = DecisionTreeClassifier()
model.fit(X, y)

# Predict on new data
new_data = [[6]]
prediction = model.predict(new_data)

# Print the predicted value
print(prediction)
