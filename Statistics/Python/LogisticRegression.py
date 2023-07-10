# Logistic regression, as mentioned earlier, is a widely used statistical model for binary classification. While it shares similarities with linear regression, it involves the use of the logistic function to transform the linear equation and model probabilities. Understanding the logistic function and the interpretation of coefficients in logistic regression may require some familiarity with concepts like odds ratios and maximum likelihood estimation. However, once the foundational concepts are understood, logistic regression can be a powerful tool for predicting binary outcomes.

from sklearn.linear_model import LogisticRegression

X = [[1], [2], [3], [4], [5]]
y = [0, 0, 0, 1, 1]

model = LogisticRegression()
model.fit(X, y)

new_data = [[6]]
prediction = model.predict(new_data)

print(prediction)
