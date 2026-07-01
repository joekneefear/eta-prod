def index_mapper(entry : str, headers : list):
    for i in range(0,len(headers)):
        if entry == headers[i]:
            index = i
            break
    return index
