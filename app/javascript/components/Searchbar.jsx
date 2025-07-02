import React, { useState, useEffect } from 'react';
import { useDebounce } from 'use-debounce';

const Searchbar = () => {

    const [searchTerm, setSearchTerm] = useState('');

    const [debouncedSearchTerm] = useDebounce(searchTerm, 150)
	
    const [searchResults, setSearchResults] = useState([]);
	
    const [showResults, setShowResults] = useState(false);
	
    const handleChange = (e) => {

        setSearchTerm(e.target.value);
		
    };

    const handleSelect = () => {
        setSearchTerm('');
    };

	useEffect(() => { 
	  if (debouncedSearchTerm) {
	    async function searchStocks() {
	      try {
	        const response = await fetch(`/search?q=${debouncedSearchTerm}`)
	        const data = await response.json()
        
	        setSearchResults(data)
	        console.log(data)
        
	        const timer = setTimeout(() => {
	          setShowResults(true);
	        }, 0);
        
	        return () => clearTimeout(timer);
        
	      } catch (error) {
	        console.log(error)
	      }
	    }
	    searchStocks();
	  } else {
	    setSearchResults([]);
	    setShowResults(false);
	  }
	}, [debouncedSearchTerm]);
	

    return (

    <>

    <div class='nav-search-div-two'>

    <div class='search-svg-div'>

    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="24" height="24">
          <path 
            d="m14 14-2.867-2.867m1.534-3.8A5.333 5.333 0 1 1 2 7.333a5.333 5.333 0 0 1 10.667 0Z" 
            stroke="#32302F" 
            stroke-width="1.8" 
            stroke-linecap="round" 
            stroke-linejoin="round"
            fill="none">
          </path>
        </svg>

    </div>

    <div class='search-parent'>

    <input type='search' className='searchbar' placeholder="Search name or symbol" value={searchTerm} onChange={handleChange} />

  </div>
  </div>
  <div className="search-results-container">

  		{debouncedSearchTerm && showResults && (
			<ul className="search-results">
			{searchResults.map((stock) => (
				<a class='search-text'href={`/stocks/${stock.symbol}`} onClick={handleSelect}>
				<li key={stock.id} className="search-result-item" onClick={ handleSelect }>
				<div>{stock.symbol}</div>
				<div>{stock.name}</div>
                </li>
				</a>
				))}
				</ul>
                )}
				
				{debouncedSearchTerm && searchResults.length === 0 && showResults && (
				<div className="search-result-item">No stocks found</div>
				)}
				</div>
				</>
            );
          };
		  
		  export default Searchbar;