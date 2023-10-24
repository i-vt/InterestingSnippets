#Linear regression is a straightforward and intuitive statistical model used to analyze the relationship between a dependent variable and one or more independent variables. The basic concept of fitting a line to a set of data points is relatively easy to grasp. It involves minimizing the sum of squared differences between the observed data and the predicted values. Linear regression also has a clear interpretation of coefficients and can provide insights into the direction and strength of relationships between variables.

from sklearn.linear_model import LinearRegression

X = [[1], [2], [3], [4], [5]]
y = [2, 4, 6, 8, 10]

model = LinearRegression()
model.fit(X, y)

new_data = [[6]]
prediction = model.predict(new_data)

print(prediction)
