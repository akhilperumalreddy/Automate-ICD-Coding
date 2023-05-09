import pandas as pd
import matplotlib.pyplot as plt
from collections import Counter
import nltk
nltk.download('punkt')
from nltk.tokenize import word_tokenize

# Read the CSV file
#train_df = pd.read_csv(r"/content/sample_data/train_notes_pv1_full.csv", engine = 'python',error_bad_lines=False)
train_df = pd.read_csv('../data/parallel/train_ds_notes.csv')
test_df = pd.read_csv('../data/parallel/test_ds_notes.csv')
dev_df = pd.read_csv('../data/parallel/dev_ds_notes.csv')

# Concatenate the three DataFrames vertically
all_data_df = pd.concat([train_df, test_df, dev_df], axis=0)

# Concatenate all text data into a single string
all_text = " ".join(all_data_df['text'])
# Tokenize the text and count the frequency of each word
tokens = word_tokenize(all_text)
word_freq = dict(Counter(tokens))

# Filter out words with frequency less than 10000
#word_freq = {k:v for k,v in word_freq.items() if v>=10000}

# Sort the words by frequency in descending order
sorted_words = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)

top_words = dict(sorted_words[:30])
print("Summary: ")
print("Total distinct words:",len(sorted_words))
print("Top 30 words:",top_words.keys())
print("Top 30 words count:",top_words.values())
print("Train data size:",len(train_df))
print("Test data size:",len(test_df))
print("Dev data size:",len(dev_df))
sum = 0
for k,v in sorted_words:
  sum += v
print("Total words",sum)

sum = 0
for x in top_words.values():
  sum += x
print("Total removed words", sum)

# Remove top words from text and create new column 'new_text'
def remove_top_words(text):
    words = word_tokenize(text)
    filtered_words = [word for word in words if word not in top_words]
    return " ".join(filtered_words)

train_df['new_text'] = train_df['text'].apply(remove_top_words)
test_df['new_text'] = test_df['text'].apply(remove_top_words)
dev_df['new_text'] = dev_df['text'].apply(remove_top_words)
train_df.to_csv('../data/parallel/new_train_ds_notes.csv', index=False)
test_df.to_csv('../data/parallel/new_test_ds_notes.csv', index=False)
dev_df.to_csv('../data/parallel/new_dev_ds_notes.csv', index=False)
# Convert the dictionary to a list of tuples and take the top 10 tuples
top_10 = sorted(top_words.items(), key=lambda x: x[1], reverse=True)[:10]

# Plot a histogram of the top 10 frequent words
plt.bar([word[0] for word in top_10], [word[1] for word in top_10])
plt.xlabel('Words')
plt.ylabel('Frequency')
plt.title('Top 10 Frequent Words')
plt.savefig('top_words.png')




