#  Association rules, also known as market basket analysis, focus on discovering relationships and patterns in large datasets. While the basic concept of association rules, such as the Apriori algorithm, is relatively straightforward, understanding the technical details and dealing with measures like support, confidence, and lift can be challenging. Association rules can be useful in certain domains, such as market analysis or recommendation systems, but they may require a deeper understanding of data mining concepts and techniques.

from mlxtend.frequent_patterns import apriori
from mlxtend.frequent_patterns import association_rules

dataset = [['Apple', 'Banana', 'Coke'],
           ['Apple', 'Banana'],
           ['Apple', 'Banana', 'Eggs'],
           ['Apple', 'Coke']]

one_hot_encoded = lambda x: pd.Series(1, index=x)
one_hot_dataset = dataset.applymap(one_hot_encoded).fillna(0)

frequent_itemsets = apriori(one_hot_dataset, min_support=0.5, use_colnames=True)

rules = association_rules(frequent_itemsets, metric="lift", min_threshold=1)

print(rules)
